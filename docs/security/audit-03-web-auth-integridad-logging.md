# Audit 03 — Backend/API/Web · A07 Autenticación · A08 Integridad · A09 Logging · A10 Excepciones

> Alcance: backend (5 microservicios Node/Express + `packages_shared/security`) y
> frontend web (`apps/admin-web`). Basado en `audit-00-mapeo.md`. Referencia:
> OWASP Top 10:2025. Fecha: 2026-07-24. Método: revisión estática con evidencia
> `archivo:línea`; sin hallazgos inventados; limitaciones (retención de logs,
> consola cloud) indicadas.

## Tabla resumen

| ID | Categoría | Hallazgo | Severidad | Evidencia |
|----|-----------|----------|-----------|-----------|
| A07-1 | Autenticación | Gestión de sesión robusta: rotación de refresh + reuse-detection + cookies endurecidas | ✅ Correcto | `authController.js:33-36,306,385`; `refreshTokenModel.js` |
| A07-2 | Autenticación | MFA/WebAuthn con challenge server-side de un solo uso | ✅ Correcto | `passkeyController.js:126,161,301` |
| A07-3 | Autenticación | Recuperación de contraseña: single-use + expiry + anti-enumeración | ✅ Correcto | `resetTokenModel.js:26,52-60`; `passwordController.js:29-55` |
| A07-4 | Autenticación | Login por descubrimiento usa `Math.random()` para la **clave de lookup** del challenge (no el challenge) + almacenamiento dual | Info | `passkeyController.js:224,246-248` |
| A08-1 | Integridad datos | Firma de webhooks (HMAC) verificada; QR autenticado (GCM); sin deserialización insegura | ✅ Correcto | `webhookController.js:149`; `cryptoService.js` |
| A08-2 | Integridad software | `@import` de Google Fonts sin SRI y SPA sin CSP propia | Baja | `admin-web/src/index.css:1`; `admin-web/index.html` |
| A08-3 | Integridad software | Actions de CI sin pin a SHA (integridad del pipeline) | Media | (ver `audit-01` A03-2) |
| A09-1 | Logging | Logging estructurado (JSON) con **redacción fuerte** de secretos/PII | ✅ Correcto | `logger.js:33-84` |
| A09-2 | Logging | Eventos de seguridad con códigos + correlación `X-Request-ID` | ✅ Correcto | `jwtVerify.js`; `helmetConfig.js:169` |
| A09-3 | Alertas | **Sin SIEM/alerting/umbrales**: solo stdout; sin detección activa | **Media** | ausencia (grep sentry/datadog/alert = 0) |
| A10-1 | Excepciones | Rate limiter cae a **MemoryStore por proceso** si falta Redis → fail-open entre réplicas | **Media** | `rateLimiter.js:19,80-88` |
| A10-2 | Excepciones | Errores no verbosos, shutdown graceful, timeouts salientes, webhook fail-closed | ✅ Correcto | `errorHandler.js:21`; `main.js` shutdown; `llmClientService.js:217` |

**Limitación global:** la **retención y el destino final** de los logs (stdout →
Railway) y la existencia de reglas de alerta a nivel de plataforma no son
auditables desde el repo; requieren acceso a la consola cloud.

---

## A07 — Fallos de autenticación · Severidad global: Baja (sin hallazgos relevantes)

### A07-1 (correcto) — Gestión de sesión
- **Cookies de refresh endurecidas:** `httpOnly:true`, `secure: env.IS_PRODUCTION`,
  `sameSite:'strict'`, `path` acotado y `maxAge` (`authController.js:33-36`; idéntico
  en login por passkey `passkeyController.js:365-369`). `sameSite:strict` mitiga CSRF.
- **Rotación con familias + reuse-detection atómico:** cada `/refresh` consume el
  token (`consumeAtomically`, `authController.js:385`) y emite el siguiente en la
  misma familia; ante reuso/consumido/expirado/carrera se **revoca toda la familia**
  (`:306,370,379,387,397,401`). Expiración **server-side** (`expires_at`,
  `refreshTokenModel.js:44,64`), no dependiente del `maxAge` de la cookie.
- **Logout:** revoca el `jti` del access token en blacklist Redis con TTL = exp
  (`authController.js:296`); limpia la cookie (`:311`).
- **Comparación de contraseña en tiempo constante-ish anti timing/enumeración:** la
  comparación se ejecuta aunque `user` sea null (`authController.js:129`).

### A07-2 (correcto) — MFA / WebAuthn
`@simplewebauthn/server` con `verifyRegistrationResponse`/`verifyAuthenticationResponse`.
El **challenge se guarda server-side** (`saveChallenge`, Redis) y se **consume una
sola vez** (`getAndRemoveChallenge`, `passkeyController.js:126,161,301`) → anti-replay;
se validan `expectedChallenge`, `expectedOrigin`, `expectedRPID` (`:172-174`) y se
persiste el `counter` (detección de clonación de autenticador, `:185-192`).

### A07-3 (correcto) — Recuperación de contraseña
Token de reset de un solo uso (`usado=false` + `markAsUsed`), con **expiración**
(`expira_en` DEFAULT NOW()+1h y filtro `gt('expira_en', now)`, `resetTokenModel.js:52-60`),
que **invalida tokens previos** al emitir uno nuevo (`:26-28`). `forgot-password`
responde SIEMPRE genérico y entrega el token **por email** (no en la respuesta HTTP),
guardándolo hasheado (`passwordController.js:29-55`). Anti-enumeración correcto.

### A07-4 (Info) — Clave de lookup del challenge en login por descubrimiento
En el flujo de login por descubrimiento, `challengeKey = 'global_login_' +
Math.random()...` (`passkeyController.js:224`) y el challenge se guarda bajo **varias
claves** (por `options.challenge` y por `challengeKey`, `:246-248`).
- **Impacto:** bajo — el **challenge en sí** lo genera `@simplewebauthn`
  (CSPRNG); `Math.random()` solo produce un **handle de búsqueda temporal**, no
  material criptográfico. El almacenamiento dual es un *code smell* mantenible.
- **Remediación:** usar `crypto.randomUUID()` para el handle y unificar a una sola
  clave de challenge por intento para simplificar y evitar entradas huérfanas en Redis.

---

## A08 — Fallos de integridad de software/datos · Severidad global: Baja–Media

### A08-1 (correcto) — Firma, autenticación de datos y deserialización
- **Webhooks Stripe:** `stripe.webhooks.constructEvent(rawBody, signature, secret)`
  verifica HMAC-SHA256 antes de procesar (`webhookController.js:149`); rechazo 400 si
  falta firma o no valida.
- **QR de acceso:** payload cifrado+autenticado con AES-256-GCM; el `JSON.parse` se
  hace **tras** verificar el authTag (integridad garantizada, `cryptoService.js`).
- **Sin deserialización insegura:** no hay `yaml.load`, `node-serialize`,
  `vm.runIn*` ni `unserialize` en el código (grep = 0). `JSON.parse` solo sobre datos
  confiables/autenticados.

### A08-2 (Baja) — Recursos de terceros sin control de integridad en el panel
`apps/admin-web/src/index.css:1` importa la fuente Inter desde
`fonts.googleapis.com` vía `@import` (sin SRI; CSS `@import` no admite `integrity`).
El `index.html` solo carga el bundle local (`/src/main.tsx`, sin scripts externos),
pero **la SPA no define una CSP propia** (meta/header).
- **Impacto:** bajo — dependencia de un origen de terceros para CSS de fuente; sin
  CSP, un XSS (no encontrado hoy) no tendría mitigación de defensa en profundidad.
- **Remediación:** (a) self-host de la fuente Inter (elimina el tercero y el FOUT);
  (b) añadir CSP a la SPA (via `<meta http-equiv>` o cabecera del host estático):
  `default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self' <APIs>`.

### A08-3 (Media) — Integridad del pipeline de build
Cruce con `audit-01` **A03-2**: las GitHub Actions se referencian por **tag mutable**
(`@v2`,`@v1`,`@v4`) y no por SHA. En los workflows de release (que manejan secretos de
firma) esto es un riesgo de **integridad de la cadena de construcción**. Remediación:
pin a SHA (ver `audit-01`).

---

## A09 — Fallos de registro y alertas · Severidad global: Media

### A09-1 y A09-2 (correcto) — Registro
- **Redacción robusta** antes de serializar (en prod **y** dev): `logger.js:33`
  redacta por **clave** sensible (`pass/secret/token/authorization/api key/cookie/
  card/cvv/ssn/private key/refresh|access|id token/client_secret/webhook_secret/
  inter_service_secret/service_role/pin_terminal/bearer`) y por **patrón de valor**
  (`sk_/rk_live|test`, `whsec_`, `sb_secret_`, `Bearer …`) dentro de cualquier string
  (`:39-47`), con límite de profundidad y sin mutar el objeto original (`:69-84`).
- **Eventos de seguridad** con códigos consistentes: `JWT_BLACKLISTED`,
  `INSUFFICIENT_ROLE`, `JWT_MISSING_CLAIMS`, `INTER_SERVICE_AUTH_FAILED`,
  `WEBHOOK_SIGNATURE_INVALID`, etc. **Correlación** por `X-Request-ID`
  (`helmetConfig.js:169`). Formato JSON apto para ingestión.

### A09-3 (Media) — Sin detección/alertas activas (SIEM/umbrales)
**Evidencia:** no hay integración con Sentry/Datadog/CloudWatch/PagerDuty ni envío de
alertas (grep `sentry|datadog|pagerduty|opsgenie|cloudwatch|slack webhook` = 0). El
único destino es **stdout** (`transports.Console`); no existen reglas ni umbrales
que disparen alerta ante señales ya registradas (p. ej. ráfaga de
`WEBHOOK_SIGNATURE_INVALID`, `INTER_SERVICE_AUTH_FAILED`, bloqueos de cuenta o picos
de 401/403).
- **Impacto:** los eventos se registran pero **nadie es notificado**; un ataque
  (fuerza bruta distribuida, sondeo de webhooks, abuso M2M) puede pasar inadvertido
  hasta revisar logs manualmente. Sin detección, el MTTD es alto.
- **Remediación:** (a) enviar los logs a un colector (Sentry para errores + un
  SIEM/log store para eventos de seguridad); (b) definir **alertas con umbral** sobre
  los códigos de evento ya existentes (p. ej. > N `WEBHOOK_SIGNATURE_INVALID`/5 min,
  cualquier `INTER_SERVICE_AUTH_FAILED`, tasa de 401 en `/login`); (c) documentar
  retención mínima (p. ej. 90 días) y verificarla en Railway.
- **Qué necesitaría:** consola Railway/observabilidad para confirmar retención,
  destino de stdout y si ya hay alguna alerta a nivel de plataforma.

---

## A10 — Manejo incorrecto de condiciones excepcionales · Severidad global: Media

### A10-1 (Media) — Rate limiter con degradación fail-open
**Evidencia:** `rateLimiter.js:19` documenta el fallback y `:80-88` lo implementa: si
no hay `redisClient`, `buildRedisStore` devuelve `null` y express-rate-limit usa
**MemoryStore en proceso**.
- **Impacto:** en el despliegue multi-réplica de Railway, un store en memoria **no se
  comparte entre instancias** → el límite efectivo se multiplica por el nº de réplicas
  y un atacante distribuido obtiene N× intentos. Afecta especialmente a los limitadores
  **anti-fuerza-bruta** de `/login` (por IP y por cuenta), debilitando ese control de
  A07. Si Redis cae **en runtime**, el comportamiento por defecto de express-rate-limit
  ante error de store tiende a **fail-open** salvo configuración explícita.
- **Remediación:** (a) tratar Redis como **dependencia dura** para los limitadores de
  auth: si el store no está disponible, **fail-closed** en `/login`/`/register`
  (rechazar o degradar a un límite muy estricto), no MemoryStore silencioso; (b) fijar
  explícitamente el manejo de error de store (`passOnStoreError:false`); (c) alertar
  (A09-3) cuando se active el fallback a memoria.

### A10-2 (correcto) — Otros controles de excepción
- **Errores no verbosos:** `errorHandler.js:21` (`isProduction`) nunca expone stack
  ni rutas internas en prod; mapeo controlado por tipo (validación/JWT/CORS/DB/Stripe).
- **Fail-closed donde importa:** el webhook responde **503** si el store de
  idempotencia no está disponible (no arriesga doble-procesamiento) — patrón correcto.
- **Atomicidad/rollback:** los flujos críticos usan **RPC SQL atómicas**
  (`registrar_pago_efectivo`, `increment_offer_usage`) y `consumeAtomically` para
  refresh; el claim de webhook es atómico por PK. (Nota menor: supabase-js no ofrece
  transacciones multi-sentencia; las secuencias de escritura no críticas no son
  transaccionales por diseño — mitigado encapsulando lo crítico en RPC.)
- **Shutdown graceful:** `SIGTERM`/`SIGINT` → `server.close` + `redis.quit` + force-exit
  temporizado (`*/main.js`).
- **Timeouts salientes:** LLM 45s con `AbortController` (`llmClientService.js:217`),
  axios biométrico 5s (`biometricNotificationService.js:60`), Open Food Facts con
  timeout — evita cuelgues por dependencia lenta.

---

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Rate limiters de auth **fail-closed** + `passOnStoreError:false` (no MemoryStore silencioso) | A10-1 |
| 2 | Enviar logs a SIEM/Sentry y definir **alertas con umbral** sobre los eventos ya registrados | A09-3 |
| 3 | Pin de actions de CI a SHA (integridad del pipeline) | A08-3 |
| 4 | Self-host de la fuente + CSP en la SPA del panel | A08-2 |
| 5 | `crypto.randomUUID()` para el handle de challenge + unificar almacenamiento | A07-4 |
| — | Confirmar retención/destino de logs y alertas de plataforma en Railway | A09-3 (limitación) |

> Balance: A07 (autenticación) y A08 (integridad de datos) están **bien resueltos**;
> las brechas reales de este bloque son **operativas** — falta la capa de
> **detección/alerta** (A09-3) y el rate limiting debe ser **fail-closed** para no
> anular en silencio la protección anti-fuerza-bruta (A10-1).
