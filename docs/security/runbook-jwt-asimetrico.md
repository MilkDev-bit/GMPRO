# Runbook — Activación de JWT asimétrico (A04-1 / CLD-4)

> Migración del JWT de firma **simétrica compartida (HS512)** a **asimétrica
> (RS256)**: auth-service firma con clave privada; el resto verifica con la
> pública. **Sin downtime** ni invalidar tokens vivos (convivencia). El código ya
> está en `main` y validado (5 tests + e2e con claves openssl). Este runbook es la
> parte **operativa** (generar claves + variables de entorno + despliegue por fases).

## Cómo funciona el código (ya desplegado)
- `packages_shared/security/jwtVerify.js` → `verifyToken()`: intenta **RS256 con la
  clave pública** y, si falla, cae a **HS512 con `JWT_SECRET`** (convivencia). Cada
  intento fija algoritmo+clave → sin confusión RS/HS ni `alg:none`. Lee
  `JWT_PUBLIC_KEY` **directo de `process.env`** (no hay que tocar los config de los servicios).
- `auth-service/tokenService.js`: firma **RS256** si existe `JWT_PRIVATE_KEY`; si no,
  sigue firmando HS512 (`JWT_ALGORITHM`).
- Variables (todas opcionales durante la convivencia):
  - `JWT_PUBLIC_KEY` (PEM o **base64** del PEM) — en **los 5 servicios**.
  - `JWT_VERIFY_ALGORITHMS` (default `RS256`) — en los 5 servicios.
  - `JWT_PRIVATE_KEY` (PEM o base64) + `JWT_SIGN_ALGORITHM` (default `RS256`) — **solo auth**.

> ⚠ **Manejo del secreto:** la clave PRIVADA es material de firma. Guárdala en un
> secret manager / gestor de secretos; en Railway va como variable (base64). **Nunca
> se commitea** al repo. La PÚBLICA se puede distribuir sin riesgo.

---

## Fase 0 — Generar el par de claves (offline, una vez)
```bash
# RSA 2048 (RS256). Alternativa EdDSA: openssl genpkey -algorithm ED25519 ...
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt_priv.pem
openssl pkey -in jwt_priv.pem -pubout -out jwt_pub.pem

# Codificar en base64 para pegarlas como variables de entorno (sin problemas de saltos)
base64 -w0 jwt_priv.pem > jwt_priv.b64   # → valor de JWT_PRIVATE_KEY (solo auth)
base64 -w0 jwt_pub.pem  > jwt_pub.b64    # → valor de JWT_PUBLIC_KEY  (los 5 servicios)
```
Guarda `jwt_priv.pem` en lugar seguro y **borra las copias locales** tras cargarlas.

---

## Fase 1 — Distribuir la clave PÚBLICA (sin activar la firma nueva)
En **los 5 servicios** (Railway → Variables): añade
```
JWT_PUBLIC_KEY = <contenido de jwt_pub.b64>
JWT_VERIFY_ALGORITHMS = RS256
```
**No** pongas `JWT_PRIVATE_KEY` todavía. Despliega.
- Efecto: todos **verifican** RS256 **y** HS512; se siguen **emitiendo** tokens HS512.
- **Verificación:** el sistema funciona igual que antes (los tokens actuales son HS512
  y validan por la vía simétrica). Sin cambios visibles para los usuarios.
- **Rollback:** quitar `JWT_PUBLIC_KEY` → vuelve a HS512 puro.

## Fase 2 — Activar la firma ASIMÉTRICA (solo auth-service)
En **auth-service** (Railway → Variables): añade
```
JWT_PRIVATE_KEY = <contenido de jwt_priv.b64>
JWT_SIGN_ALGORITHM = RS256
```
Despliega **solo auth-service**.
- Efecto: los tokens **nuevos** salen firmados **RS256**; los **viejos** HS512 siguen
  válidos hasta expirar (ventana = `JWT_EXPIRES_IN`).
- **Verificación** (decodifica el header de un access token recién emitido):
  ```bash
  # tras un login, toma el accessToken y mira el header (alg debe ser RS256):
  echo '<ACCESS_TOKEN>' | cut -d. -f1 | base64 -d 2>/dev/null; echo
  #   esperado: {"alg":"RS256","typ":"JWT"}
  ```
  Confirma además que un endpoint protegido de otro servicio (p. ej. fitness) acepta
  ese token RS256 (verifica con la pública) y que un token HS512 aún vigente también
  entra.
- **Rollback:** quitar `JWT_PRIVATE_KEY` de auth → vuelve a firmar HS512 (todos siguen
  aceptando ambas, así que es reversible sin cortar sesiones).

## Fase 3 — Retirar el secreto simétrico (tras la ventana de expiración)
Espera a que **todos** los tokens HS512 hayan expirado (≥ `JWT_EXPIRES_IN` + margen).

1. **Cambio de código — ✅ YA APLICADO** (rama `security/jwt-retire-hs`). En los 5
   `services/*/src/config/environment.js`, `JWT_SECRET` pasó a condicional:
   ```js
   { key: 'JWT_SECRET', required: false, validate: (v) => !v || v.length >= 64 },
   ```
   más una comprobación cruzada al final de `validateEnvironment()`:
   ```js
   if (!process.env.JWT_SECRET && !process.env.JWT_PUBLIC_KEY) {
     errors.push('  ✗ JWT: falta JWT_SECRET (HS512) o JWT_PUBLIC_KEY (RS256) — se requiere al menos uno');
   }
   ```
   Se quitó `'JWT_SECRET'` de los `REQUIRED_ENV` de `main.js` en auth/fitness/ai
   (access/payment no lo tenían). Validado: los 5 arrancan con **solo** `JWT_PUBLIC_KEY`;
   fallan si faltan **ambos**; suite auth 50/50 verde (compatibilidad hacia atrás).
   > Copias muertas `services/*/src/middlewares/jwtVerify.js` (HS512-only, 0 imports):
   > `git rm` recomendado (footgun; el verificador real es `packages_shared/security/jwtVerify.js`).

2. **ORDEN CRÍTICO DE DESPLIEGUE** (no invertir):
   1. **Primero** despliega este código a **los 5 servicios** (aún con `JWT_SECRET` puesto).
   2. **Solo después** de que los 5 estén arriba con el código nuevo, quita `JWT_SECRET`
      de Railway servicio por servicio (canary). Si quitas la variable **antes** de
      desplegar el código, los servicios viejos (con `required:true`) **no arrancan**.
   3. Tras cada retirada, comprueba `/health` del servicio y un endpoint protegido con
      un token RS256.
3. **Rotación:** documentar la rotación periódica de la clave privada (regenerar par →
   Fase 1 con la nueva pública en verify (multi-key) → Fase 2 con la nueva privada →
   retirar la vieja). Para rotación fluida conviene añadir `kid` a los tokens en una
   iteración futura.

---

## Segregación de secretos (CLD-4)
- La **privada vive SOLO en auth-service** (idealmente secret manager/HSM).
- Se elimina el secreto simétrico **compartido** (`JWT_SECRET`) tras la Fase 3.
- El `INTER_SERVICE_SECRET` (M2M) sigue su propia rotación (no es parte de esta migración).

## Resumen de variables por fase

| Variable | Fase 1 | Fase 2 | Fase 3 | Dónde |
|----------|:------:|:------:|:------:|-------|
| `JWT_SECRET` | ✅ | ✅ | ❌ (retirar) | 5 servicios |
| `JWT_PUBLIC_KEY` | ✅ | ✅ | ✅ | 5 servicios |
| `JWT_VERIFY_ALGORITHMS=RS256` | ✅ | ✅ | ✅ | 5 servicios |
| `JWT_PRIVATE_KEY` | — | ✅ | ✅ | solo auth |
| `JWT_SIGN_ALGORITHM=RS256` | — | ✅ | ✅ | solo auth |

## Validación ya realizada
- `jwtAsymmetric.test.js` (5 tests): acepta RS256, sigue aceptando HS512, rechaza
  confusión RS/HS, expirado y `alg:none`.
- e2e con claves **openssl PEM + base64**: token RS256 nuevo → OK; token HS512 viejo → OK.
