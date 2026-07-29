# Remediación — Fase 3 (cambios ESTRUCTURALES)

> Rama objetivo: `security/fase-3-estructural`. **Propuestas + implementación en
> rama — NUNCA merge directo a main.** Cubre CLD-1, A04-1/CLD-4, A06-1, A01-3,
> IOS-4. Fecha: 2026-07-24.
>
> Restricción de entorno: git bloqueado (`.git/*.lock`) y sin toolchain
> DB/Flutter/iOS → los cambios de código están **aplicados y validados con jest**
> donde es posible; la ejecución en Supabase/App Store queda como **manual mía**.
> Rama + commit al final.

## Estado

| # | Hallazgo | Implementado en código | Requiere ejecución manual (fuera del repo) |
|---|----------|------------------------|--------------------------------------------|
| 1 | CLD-1 roles de BD mínimo privilegio | Migración SQL `009_*` (roles/grants/policies) | **Ejecutar en Supabase** + rotar `service_role` |
| 2 | A04-1/CLD-4 JWT asimétrico | ✅ Código + **5 tests verdes** (convivencia) | Generar par de claves + set env por servicio |
| 3 | A06-1 threat model | ✅ `docs/security/threat-model.md` (DFD+STRIDE) | Revisión del equipo; diagramar formal |
| 4 | A01-3 SSRF guard cableado | ✅ `fetchUserImage` + **39 tests verdes** | — (wire al añadir el endpoint multimodal) |
| 5 | IOS-4 OAuth por Universal Links | 🔷 Diseño + snippet + plan de transición | Requiere **nueva versión en la App Store** |

---

## 1. CLD-1 — Roles Postgres de mínimo privilegio (retirar `service_role`)
**Entregable:** `docs/database/schemas/migrations/009_least_privilege_roles.sql`
(**NO ejecutado**). Diseña un rol `svc_<servicio>` por microservicio con:
- `USAGE` en su schema + `SELECT/INSERT/UPDATE/DELETE` **solo** sobre sus tablas
  (los catálogos de fitness quedan en SELECT), `EXECUTE` sobre sus funciones.
- **Cruces mínimos** de lectura por columnas (p. ej. payment→`auth.usuarios` solo
  `id,activo,nombre,email,pin_terminal`; access→`auth.usuarios`; payment→`access.historial_accesos`).
- Como las tablas tienen **RLS deny-all** y estos roles **no** bypassan RLS, se
  añade una **POLICY permisiva `TO svc_<rol>`** por tabla (public→false OR rol→true).

El mapa de tablas se derivó de `grep .from()/.rpc()` por servicio (autoritativo de
lo que cada uno accede).
> ⚠ **Confirmar nombres de tabla contra el schema REAL** antes de aplicar (los docs
> de esquema pueden estar desincronizados: `ejercicios` vs `catalogo_ejercicios`).

### Plan de corte SIN downtime
1. **Aplicar 009** en Supabase creando los roles (con contraseñas fuertes vía
   `psql -v`), GRANTs y policies. `service_role` sigue funcionando en paralelo.
2. **Por servicio, uno a uno** (canary): cambiar `SUPABASE_SERVICE_ROLE_KEY` por la
   credencial del rol nuevo del servicio (Supabase permite conexión por rol/PG
   connection string, o una API key ligada al rol). Desplegar 1 réplica, verificar
   salud + smoke de sus endpoints, luego el resto.
3. **Orden sugerido** (de menor a mayor acoplamiento cruzado): `ai` → `fitness` →
   `access` → `auth` → `payment` (payment tiene más cruces).
4. Validar los **cruces de schema** (biometría payment→auth, historial payment→access).
5. Cuando los 5 usen su rol y estén estables ≥1 semana: **revocar** el uso rutinario
   de `service_role` y **rotarlo** (reservarlo solo para migraciones/admin).
6. Rollback: revertir la env del servicio a `service_role` (queda operativo).

---

## 2. A04-1 / CLD-4 — JWT simétrico → asimétrico (RS256/EdDSA) con convivencia
**Código (implementado y probado):**
- `packages_shared/security/jwtVerify.js`: nuevo `verifyToken()` que verifica
  **primero con la clave PÚBLICA** (RS256/EdDSA) y, si falla, **con el secreto
  simétrico viejo** (HS*), hasta que expiren los tokens antiguos. Cada intento fija
  algoritmo+clave → **sin confusión RS/HS** ni `alg:none`. Arranca si hay
  `JWT_PUBLIC_KEY` **o** `JWT_SECRET`.
- `auth-service/tokenService.js`: firma **asimétrica** si hay `JWT_PRIVATE_KEY`
  (`JWT_SIGN_ALGORITHM`, default RS256); si no, mantiene HS* → sin downtime.
- `auth-service/environment.js`: exporta `JWT_PRIVATE_KEY` (PEM o base64) y `JWT_SIGN_ALGORITHM`.

**Tests (verdes):** acepta RS256 nuevo; **sigue aceptando HS512 viejo**; rechaza
HS512 firmado con la pública como secreto (anti-confusión); rechaza expirado y
`alg:none`. Regresión de auth intacta (**50 passed**).

### Plan de rotación/segregación sin downtime
1. **Generar el par** (offline, guardar la privada de forma segura):
   ```bash
   # RS256
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt_priv.pem
   openssl pkey -in jwt_priv.pem -pubout -out jwt_pub.pem
   ```
2. **Distribuir la clave PÚBLICA** a los 5 servicios: `JWT_PUBLIC_KEY` (base64 del
   PEM) + `JWT_VERIFY_ALGORITHMS=RS256`. Aún NO firmar asimétrico → todos verifican
   ambas, siguen aceptando los HS* actuales. Desplegar.
3. **Activar la firma** solo en **auth-service**: set `JWT_PRIVATE_KEY` (base64).
   Desde aquí, los tokens NUEVOS son RS256; los viejos (HS*) siguen válidos hasta
   expirar (ventana = `JWT_EXPIRES_IN`).
4. Tras superar la ventana de expiración de los HS*: **retirar `JWT_SECRET`** de los
   verificadores (dejar solo la pública) y del firmante. **Rotar** la clave privada
   periódicamente (soporta rotación con `kid` en el futuro).
5. **Segregación (CLD-4):** dejar de compartir un único secreto; la privada vive
   SOLO en auth-service (idealmente en secret manager/HSM). Rollback: quitar
   `JWT_PRIVATE_KEY` de auth → vuelve a firmar HS* (los verificadores ya aceptan ambos).

---

## 3. A06-1 — Threat model formal
**Entregable:** `docs/security/threat-model.md` — DFD de alto nivel + límites de
confianza + **STRIDE por flujo** (pago, acceso físico, identidad, IA/PII) mapeado a
los controles existentes y huecos. Es documentación (sin riesgo de romper nada);
punto de partida para que el equipo lo complete y diagrame formalmente.

---

## 4. A01-3 — SSRF guard cableado
**Hallazgo honesto:** tras revisar los 5 servicios, **NINGÚN endpoint recibe hoy una
URL de usuario** (`grep req.body/query .*url` = 0). No hay un "punto de entrada"
existente que cablear sin inventar una feature.

**Implementado:** `services/ai-service/src/services/safeImageFetch.js` →
`fetchUserImage(url)`, la **ÚNICA vía permitida** para descargar contenido desde una
URL de usuario. Cablea el `ssrfGuard` existente (`safeFetch`/`assertSafePublicUrl`):
bloquea loopback, RFC1918 (10/172.16/192.168), link-local/metadata
(169.254.169.254), IPv6 privadas, credenciales embebidas; fuerza https,
`redirect:'error'`, timeout, y valida tipo/tamaño de imagen.

**Tests (verdes, 39 total con el suite existente):** rechaza todas las internas/
privadas/metadata/IPv6/http/credenciales, **no llama a fetch** en esos casos, y
**permite** una URL externa https legítima (IP pública) validando tipo/tamaño.

**Acción al añadir el endpoint multimodal:** invocar `fetchUserImage` (nunca `fetch`
directo de una URL de usuario). Recomendado: test/lint en CI que falle si aparece un
`fetch(` nuevo sobre input de request sin pasar por el guard.

---

## 5. IOS-4 — OAuth por URL scheme custom → ASWebAuthenticationSession + Universal Links
**Estado:** 🔷 diseño + snippet + plan (no puedo compilar/probar iOS aquí; **requiere
una nueva versión en la App Store** antes de retirar el scheme viejo).

**Cambio propuesto (Flutter):** usar `flutter_web_auth_2` (envuelve
`ASWebAuthenticationSession` en iOS y Custom Tabs en Android) con **PKCE** y callback
por **Universal Link** (associated domains), en vez del custom URL scheme
secuestrable.
```dart
// pubspec.yaml:  flutter_web_auth_2: ^3.1.0
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

Future<String> signInWithGoogleWeb() async {
  // callbackUrlScheme para iOS es 'https' cuando se usa Universal Link.
  final result = await FlutterWebAuth2.authenticate(
    url: authorizeUrlWithPkceAndState(),        // endpoint OAuth + code_challenge + state
    callbackUrlScheme: 'https',                 // Universal Link (associated domain)
  );
  final code = Uri.parse(result).queryParameters['code'];
  return exchangeCodeForToken(code!);           // intercambio server-side (backend)
}
```
**Config nativa requerida:**
- iOS `Runner.entitlements`: `com.apple.developer.associated-domains` =
  `applinks:app.gympro.com` (o el dominio real) + servir `/.well-known/apple-app-site-association`.
- Android: `intent-filter` con `android:autoVerify="true"` + `/.well-known/assetlinks.json`.
- El **REVERSE_CLIENT_ID** placeholder de `Info.plist` (IOS-4) se retira una vez
  migrado (no antes — ver transición).

**Plan de transición (sin dejar fuera a usuarios de versiones viejas):**
1. Añadir el flujo nuevo (Universal Links) **coexistiendo** con el custom scheme.
2. Publicar una **nueva versión** en App Store/Play que use el flujo nuevo.
3. Mantener el custom scheme mientras haya usuarios en versiones anteriores
   (telemetría de versión) — **NO retirarlo de golpe** (romperías el login de quien
   no actualizó).
4. Cuando la adopción de la versión nueva sea suficiente (p. ej. >95%) y tras un
   plazo, retirar el custom scheme en un release mayor.

---

## Validación: hecho vs pendiente

| Punto | jest/estático (hecho) | Manual / fuera del repo |
|-------|------------------------|--------------------------|
| CLD-1 | Paréntesis SQL revisados | Ejecutar 009 en Supabase; confirmar nombres de tabla; canary por servicio; rotar service_role |
| A04-1 | ✅ 5 tests convivencia + 50 auth | Generar par de claves; distribuir pública; activar firma en auth; retirar HS* tras expirar |
| A06-1 | ✅ doc generado | Revisión del equipo; DFD formal |
| A01-3 | ✅ 39 tests SSRF | Wire al añadir endpoint multimodal |
| IOS-4 | — (no compilable aquí) | Implementar en Flutter + associated domains + release en store |

## Comando de commit
```bash
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null
git checkout -b security/fase-3-estructural
git add packages_shared/security/jwtVerify.js \
        services/auth-service/src/services/tokenService.js \
        services/auth-service/src/config/environment.js \
        services/auth-service/tests/jwtAsymmetric.test.js \
        services/ai-service/src/services/safeImageFetch.js \
        services/ai-service/tests/safeImageFetch.test.js \
        docs/database/schemas/migrations/009_least_privilege_roles.sql \
        docs/security/threat-model.md \
        docs/security/remediation-fase3-estructural.md
git commit -m "feat(sec): Fase 3 estructural — JWT asimétrico (convivencia), SSRF guard cableado, roles BD mínimo privilegio (propuesta), threat model, plan OAuth iOS"
```
