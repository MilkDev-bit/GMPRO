# Informe consolidado de seguridad — GymPro

> Rol: CISO / auditor líder. Consolida `audit-00-mapeo.md` + `audit-01`…`audit-07`.
> Frameworks: OWASP Top 10:2025 (web/backend), OWASP API Security Top 10, OWASP
> MASVS/MASTG (Android/iOS), OWASP Cloud-Native Top 10 (CNAS). Fecha: 2026-07-24.
> Base: revisión estática con evidencia `archivo:línea`. Las verificaciones que
> exigen consola de Railway/Supabase o análisis dinámico quedan como **pendientes**.

---

## 1. Resumen ejecutivo

GymPro presenta una **postura de seguridad madura en su ingeniería**: los controles
de aplicación están bien diseñados y, en su mayoría, correctamente implementados.
El backend destaca por autenticación robusta (rotación de refresh con detección de
reuso, WebAuthn, cookies endurecidas), criptografía correcta (bcrypt, AES-256-GCM
autenticado, tokens hasheados), ausencia de inyección (SQL/NoSQL saneado, sin
comandos, XSS mitigado), control de acceso a nivel de objeto y de función, logging
estructurado con redacción fuerte de secretos, y contenedores endurecidos (non-root,
alpine, multi-stage). No se hallaron vulnerabilidades **críticas explotables** en el
código revisado ni secretos versionados en git.

El riesgo real se concentra en **tres frentes**. Primero, los **controles de release
móvil están sin finalizar**: certificate pinning con pines de relleno, RASP con
identificadores placeholder y —en Android— firma de release con el keystore de
**debug**; tal como está, las defensas anti-MITM y anti-tampering **no protegen** en
producción (severidad Alta, bloqueante de release). Segundo, el **mínimo privilegio**
es débil a nivel plataforma: una única credencial God-mode de Supabase
(`service_role`, que anula el RLS) es compartida por los cinco servicios, junto con un
secreto JWT simétrico común; el compromiso de un solo servicio implicaría el de toda
la base de datos. Tercero, faltan las capas **operativas y de cadena de suministro**:
no hay detección/alertas (SIEM), ni escaneo de dependencias/imágenes, ni SBOM, ni un
threat model formal. En conjunto: base de código sólida, pero con **brechas de
hardening de despliegue, gobernanza y observabilidad** que deben cerrarse antes de un
lanzamiento a producción de alto tráfico.

---

## 2. Tabla maestra por categoría

| Categoría OWASP | Framework | Severidad | Estado | Componente |
|-----------------|-----------|-----------|--------|------------|
| A01 Control de acceso / SSRF | Top10 Web | Baja | ✅ + latente (SSRF guard sin cablear) | Backend |
| A02 Misconfiguración | Top10 Web | **Media** | ⚠ `.dockerignore` mal ubicado | Backend/Cloud |
| A03 Cadena de suministro | Top10 Web | **Media** | ⚠ sin SCA/SBOM, actions sin SHA, sin `permissions` | CI/CD |
| A04 Fallos criptográficos | Top10 Web | Baja | ✅ (secreto simétrico compartido; `ENCRYPTION_KEY` muerta) | Backend |
| A05 Inyección | Top10 Web | — | ✅ Sin hallazgos | Backend/Web |
| A06 Diseño inseguro | Top10 Web | **Media** | ⚠ sin threat model formal | Transversal |
| A07 Autenticación | Top10 Web | Baja | ✅ Robusto | Backend |
| A08 Integridad SW/datos | Top10 Web | **Media** | ⚠ actions sin SHA; SPA sin CSP/SRI | CI/CD, Web |
| A09 Logging y alertas | Top10 Web | **Media** | ⚠ sin SIEM/alertas | Backend/Cloud |
| A10 Manejo de excepciones | Top10 Web | **Media** | ⚠ rate limiter fail-open | Backend |
| API1/2/5/6 AuthZ objeto/función/flujos | API Top10 | Baja | ✅ Correcto | API |
| API3 Propiedad de objeto | API Top10 | **Media** | ⚠ over-fetching `select('*')` | API (fitness/access) |
| API4 Consumo de recursos | API Top10 | Baja | ✅ (residual: fail-open A10) | API |
| API7 SSRF | API Top10 | Baja | ✅ latente | API (ai) |
| API9 Inventario | API Top10 | Media–Baja | ⚠ rutas sin versión duplicadas; sin OpenAPI | API (access/payment) |
| MASVS-STORAGE | MASVS Android/iOS | **Media** | ⚠ Isar sin cifrar (PII) | Móvil |
| MASVS-NETWORK | MASVS Android/iOS | **Alta** | ⚠ pines de cert placeholder | Móvil |
| MASVS-CRYPTO | MASVS Android/iOS | Baja | ✅ Keychain/Enclave OK | Móvil |
| MASVS-PLATFORM | MASVS Android/iOS | Baja | ✅ (iOS OAuth por URL scheme) | Móvil |
| MASVS-RESILIENCE | MASVS Android/iOS | **Alta** | ⚠ firma debug (Android) + RASP placeholder | Móvil |
| MASVS-CODE | MASVS Android/iOS | Media–Baja | ⚠ sin R8 nativo (Dart sí ofuscado) | Android |
| CNAS-1 Config contenedores | Cloud-Native | Baja | ✅ Endurecidos | Cloud |
| CNAS-3 IAM/privilegios | Cloud-Native | **Alta** | ⚠ `service_role` God-mode compartida | Cloud/BD |
| CNAS-4/7 Suministro imágenes | Cloud-Native | **Media** | ⚠ sin escaneo/SBOM; base por tag | Cloud/CI |
| CNAS-5 Secretos | Cloud-Native | **Media** | ⚠ env vars, sin vault/rotación | Cloud |
| CNAS-6 Red | Cloud-Native | Media–Baja | ⚠ Redis sin auth (dev); postura prod no verificable | Cloud |
| CNAS-9 Cuotas | Cloud-Native | Baja | ⚠ sin límites de recursos | Cloud |
| CNAS-10 Logging cloud | Cloud-Native | **Media** | ⚠ sin alertas centralizadas | Cloud |

Leyenda: ✅ correcto · ⚠ hallazgo abierto.

---

## 3. Top 10 riesgos del proyecto (por severidad × impacto de negocio)

1. **[Alta] Controles de red móvil no operativos — certificate pinning con pines
   placeholder** (AND-2, IOS-1). Sin pines reales, el anti-MITM no existe (o rompe la
   app). *Impacto:* interceptación de credenciales/pagos en redes hostiles.
2. **[Alta] Android release firmado con keystore de DEBUG** (AND-1). El cert de debug
   es público → cualquiera re-firma un APK manipulado. *Impacto:* apps troyanizadas
   indistinguibles de la legítima; no publicable en Play.
3. **[Alta] Credencial de BD God-mode compartida (`service_role`, bypassa RLS)**
   (CLD-1) + secreto JWT simétrico común (A04-1). *Impacto:* el compromiso de **un**
   servicio expone **toda** la PII y los datos de pago de la plataforma.
4. **[Alta→Media] RASP con configuración placeholder en Android e iOS** (AND-3, IOS-2).
   El binding de integridad/anti-repackaging no funciona. *Impacto:* apps modificadas
   (cheats, exfiltración) no se detectan; respuesta activa débil en iOS.
5. **[Media] Sin capa de detección/alertas (SIEM)** (A09-3, CLD-7). Buenos logs, pero
   nadie es notificado. *Impacto:* MTTD alto; fuerza bruta/abuso pasan inadvertidos.
6. **[Media] Rate limiter fail-open** (A10-1). Degrada a memoria por proceso si falta
   Redis. *Impacto:* la protección anti-fuerza-bruta de `/login` se debilita en
   silencio en despliegues multi-réplica.
7. **[Media] Brechas de cadena de suministro** (A03-1/2/3/4, CLD-2/3): sin SCA, SBOM
   ni escaneo de imágenes; GitHub Actions sin `permissions` ni pin a SHA; base por
   tag. *Impacto:* dependencias/imágenes vulnerables llegan a producción; riesgo de
   compromiso del pipeline de release (que maneja secretos de firma).
8. **[Media] PII cacheada sin cifrar en el móvil (Isar)** (AND-4, IOS-3). *Impacto:*
   email/nombre legibles en dispositivos rooteados/jailbroken o por análisis forense.
9. **[Media] Fuga de secretos a la capa de build + higiene/rotación** (A02-1, A02-2,
   CLD-4): `.dockerignore` mal ubicado mete `.env` en la capa builder; sin rotación.
   *Impacto:* exposición de secretos vía caché/capas de imagen.
10. **[Media] Ausencia de threat model formal** (A06-1) + higiene de API (over-fetching
    `select('*')` API3, inventario de rutas API9). *Impacto:* flujos nuevos nacen sin
    controles (p. ej. el SSRF latente); fuga futura de columnas; superficie ampliada.

> Los ítems 1, 2 y 4 son **bloqueantes de release móvil**; el 3 es el de mayor
> impacto potencial en caso de brecha de un servicio.

---

## 4. Plan de remediación priorizado

### Fase 1 — Quick wins (< 1 semana)
Cambios de configuración/valores, bajo riesgo, alto retorno:
- **Pines SPKI reales** (leaf + backup) y mantener kill-switch activo — AND-2/IOS-1.
- **Signing config de release** propio en Android (keystore vía secreto CI) — AND-1.
- **Completar RASP**: `packageName/bundleIds = com.gympro.mobile`, `signingCertHashes`,
  `teamId` reales — AND-3/IOS-2.
- **`./.dockerignore` en la raíz** (`**/.env*`) y borrar `.env.bak.*` — A02-1/A02-2.
- **`permissions: contents: read`** en los 4 workflows + **pin de actions a SHA** — A03-1/A03-2.
- **Pin de imagen base por digest** (`node:22-alpine@sha256:…`) — CLD-2.
- **Redis con `--requirepass`** y no publicar puertos internos en compose — CLD-5.
- **`select('*')` → columnas explícitas** (patrón `SAFE_COLUMNS`) en fitness/access — API3.
- **Consolidar rutas a `/api/v1`** y deprecar las no versionadas — API9.
- **Eliminar `ENCRYPTION_KEY`** muerta (o marcarla para uso real) — A04-2.

### Fase 2 — Mediano plazo (1–4 semanas)
- **Rate limiters de auth fail-closed** (`passOnStoreError:false`, sin MemoryStore
  silencioso) + alerta al activarse el fallback — A10-1.
- **SCA + escaneo de imágenes + SBOM en CI**: Dependabot, `npm audit`/OSV, Trivy/Grype,
  CycloneDX; gate en HIGH/CRITICAL — A03-3/A03-4/CLD-3.
- **Detección y alertas**: exportar logs a SIEM/Sentry; umbrales sobre eventos ya
  registrados (`WEBHOOK_SIGNATURE_INVALID`, `INTER_SERVICE_AUTH_FAILED`, 401 en
  `/login`) — A09-3/CLD-7.
- **Cifrar Isar** (clave en Keychain/Keystore) o dejar de cachear PII; iOS
  `NSFileProtectionComplete` — AND-4/IOS-3.
- **CSP en la SPA** del panel + self-host de la fuente — A08-2.
- **Hardening de contenedores**: `cap_drop:[ALL]`, `no-new-privileges`, `read_only`,
  límites de CPU/mem — CLD-6.
- **R8/minify** en Android (con `proguard-rules.pro`) — AND-5.
- **OpenAPI** por servicio como inventario formal — API9.

### Fase 3 — Estructural / arquitectónico (> 1 mes)
- **Mínimo privilegio en BD**: roles Postgres por servicio con GRANTs acotados; retirar
  la `service_role` compartida del uso rutinario — CLD-1.
- **Firma JWT asimétrica** (RS256/EdDSA): auth-service firma, el resto verifica con
  clave pública; segregar y **rotar** secretos por servicio — A04-1/CLD-4.
- **Threat model formal** (DFD + STRIDE + límites de confianza) integrado al SDLC y al
  checklist de PR; cablear `ssrfGuard` en cualquier flujo con URL de usuario — A06-1/A01-3.
- **OAuth móvil vía Universal Links/ASWebAuthenticationSession** (retirar URL scheme
  custom) — IOS-4.
- **Gestor de secretos/rotación** (Vault/Secret Manager) si se escala fuera de Railway — CLD-4.

---

## 5. Gobernanza: procesos y herramientas para prevenir la recurrencia

**Automatización en CI/CD (shift-left):**
- **SAST:** CodeQL o Semgrep en cada PR (detecta inyección, secretos, patrones inseguros).
- **SCA:** Dependabot/Renovate + `npm audit`/OSV-Scanner con gate por severidad.
- **SBOM:** CycloneDX (Syft) por servicio e imagen, adjunto a cada release.
- **Escaneo de contenedores:** Trivy/Grype sobre las imágenes; opcional firma con Cosign
  y verificación en deploy.
- **Secret scanning:** gitleaks en CI **y** pre-commit (evita el problema de raíz de
  los `.env`/`.bak`).
- **Lint de config/IaC:** hadolint (Dockerfiles), validación de `docker-compose`; cuando
  se adopte IaC declarativa, `tfsec`/`checkov`.

**Verificación dinámica:**
- **DAST:** OWASP ZAP contra un entorno de staging de las APIs (recurrente).
- **Móvil:** MobSF automatizado (MASTG) + un **checklist de release** que bloquee si
  pines/RASP/firma están en placeholder.
- **BOLA/RLS:** ejecutar en CI el pentest ya existente (`docs/security/rls_bola_pentest.mjs`).

**Procesos:**
- **Threat modeling** como paso obligatorio del diseño de features que toquen flujos
  críticos (pago, acceso físico, identidad, IA/PII).
- **Checklist de seguridad en PR** (authZ de objeto, columnas explícitas, validación de
  esquema, no `select('*')`, secretos).
- **Gestión de secretos:** política de rotación y segregación por servicio; revisión
  trimestral de accesos (principio de mínimo privilegio).
- **Observabilidad como requisito de "definition of done":** todo evento de seguridad
  con código debe tener una alerta con umbral asociada.
- **Revisión periódica de la consola cloud** (Railway/Supabase) para cerrar las
  verificaciones pendientes: RLS por tabla, roles/grants, exposición de red, ACL de
  Storage, retención y alertas de logs.

---

## Anexo — Pendientes que requieren acceso fuera del repositorio
- **Supabase:** confirmar RLS habilitado por tabla, roles/grants, ACL de Storage
  (avatares), uso real de `service_role`. (A02-4, CLD-1)
- **Railway:** roles IAM del proyecto, servicios públicos vs. privados, Redis add-on
  (auth/TLS), límites de recursos, retención/alertas de logs. (A02-4, CLD-5/6/7)
- **TLS de edge:** versión mínima, cifrados, redirección HTTP→HTTPS. (A04-4)
- **Dinámico:** `npm audit` real (registry bloqueado en el entorno de auditoría),
  pinning móvil contra proxy MITM, cifrado efectivo de Isar en dispositivo. (A03-3, MASVS)
