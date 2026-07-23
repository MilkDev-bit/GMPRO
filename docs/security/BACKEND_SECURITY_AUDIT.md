# GymPro — Reporte Ejecutivo de Auditoría de Seguridad (Backend)

**Alcance:** los 6 microservicios (auth, access, fitness, payment, ai, reception-hardware-controller) y la capa compartida `packages_shared/security`.
**Metodología:** triage dirigido, distinción explícita entre *confirmado* y *descartado*, fixes completos verificados con tests, y validación de concurrencia contra infraestructura real (Postgres/Redis efímeros en CI).

---

## 1. Vulnerabilidades mitigadas (confirmadas y corregidas)

| # | Vulnerabilidad | Servicio | Severidad | Mitigación |
|---|----------------|----------|-----------|------------|
| 1 | **Reuso/replay de refresh token** (sin detección) | auth | Alta | Familias de tokens + rotación; reusar un token consumido **revoca toda la familia** (RFC 6819 / OAuth BCP) |
| 2 | **Sin expiración server-side del refresh token** | auth | Media | Expiración en BD como autoridad (integrada al modelo de familias) |
| 3 | **Sesión única / sin multi-dispositivo** | auth | Media | Tabla `refresh_tokens` con `family_id` por dispositivo |
| 4 | **Blacklist de access token desconectada** — el logout no revocaba nada | auth | Media-Alta | `req.redisClient` inyectado + rutas como factory que leen la blacklist |
| 5 | **IP spoofing en rate limiter** (CWE-348) — se tomaba el XFF más a la izquierda | shared | Media-Alta | `getRealIp` = `req.ip` (respeta `trust proxy`) |
| 6 | **Rate limit por IP en vez de por usuario** (orden de middlewares) | access/auth | Media | `staffOnly`/`jwtVerify` **antes** del limiter |
| 7 | **Spam de registro / email-bombing** — `skipSuccessfulRequests` apagaba el límite en altas exitosas | auth | Media | Limiter dedicado de `/register` que cuenta todo |
| 8 | **Fuerza bruta distribuida contra una cuenta** (solo por IP) | auth | Media | Limiter por-cuenta (email), independiente de IP |
| 9 | **BOLA/IDOR en emisión de tickets** — un socio emitía pases a nombre de otro | access | Alta | RBAC staff-only + candado de propiedad `usuario_id` |
| 10 | **BOLA/IDOR en gestión de sesiones** | auth | Alta | Revocación con candado `WHERE user_id = $me` |
| 11 | **Bypass XSS por orden de normalización** — NFKC corría tras el escape | shared | Media | Reordenado: normalize → strip control → xss → escape |
| 12 | **Recursión sin límite** (CWE-674, DoS) en el sanitizador | shared | Baja | Límite de profundidad (32) |
| 13 | **Caracteres de control sin filtrar** (null-byte, CRLF) | shared | Baja | Strip de C0/DEL preservando `\t\n\r` |
| 14 | **Evasión de detección de prompt injection** (Unicode fullwidth/zero-width) | ai | Baja | NFKC + strip zero-width antes del matching; patrones de prompt-leaking |
| 15 | **Fuga de mensaje interno en errores 5xx** (CWE-209) | shared | Baja | Mensaje genérico en producción para 5xx con `statusCode` |
| 16 | **Fuga de datos sensibles en logs** (CWE-532) — sin redacción | shared | Media | Filtro de redacción por clave + patrón de valor (JWT/Stripe/Supabase/Bearer) |
| 17 | **Command injection ADMS/ZKTeco** (CWE-93) | access | Alta | Sanitización TAB-delimited + validación de frontera |
| 18 | **Secretos hardcodeados** (CWE-798) | payment | Alta | Externalizados a entorno + rotación |
| 19 | **Idempotencia de pagos en efectivo** | payment | Media | Claim atómico (rondas previas) |

## 2. Hardening aplicado (preventivo / defensa en profundidad)

- **SSRF Guard** (`ssrfGuard.js`): validador reutilizable (bloquea IPs privadas/loopback/link-local y metadatos cloud `169.254.169.254`, exige https, rechaza credenciales embebidas, no sigue redirects). Pieza pasiva lista para el roadmap multimodal; **no** se cablea en llamadas internas (que van a IPs privadas legítimas).
- **Defensa en capas contra Prompt Injection**: sandbox `<user_input>` con stripping de delimitadores + system prompt defensivo + output-encoding delegado al cliente.
- **CI de concurrencia contra infraestructura real**: tests que disparan `Promise.all` contra Postgres/Redis efímeros y prueban que **solo una** operación gana la carrera:
  - Rotación de refresh token (consumo atómico → 1 rota, resto 401, reuse revoca familia).
  - Candado BOLA de sesiones a nivel SQL.
  - Revocación de access token en logout (Redis real).
  - **Idempotencia del webhook de Stripe** (20 entregas concurrentes del mismo `evt_…` → 1 reclama).
- **Estandarización de testing**: `jest.config.js` en los 5 servicios Node; workflows `test.yml` (unitarios) e `integration.yml` (matrix auth+payment con Postgres/Redis).
- **`trust proxy` = 1** en los 5 servicios (prerequisito de la resolución segura de IP).

## 3. Componentes validados como seguros (sin cambios necesarios)

- **Webhook de Stripe**: verificación de firma con `constructEvent` sobre **raw Buffer** + `whsec_`, tolerancia 300s (anti-replay), idempotencia por **PK atómica** (`event_id`) fail-closed, y aprovisionamiento **idempotente** (asignación absoluta de vigencia, no acumulativa) → sin doble cobro/alta.
- **CORS** (`corsConfig.js`): whitelist exacta, `*` prohibido (mata el proceso), HTTPS forzado en prod, `credentials:true` solo con origen validado.
- **Helmet** (`helmetConfig.js`): CSP maximalista, HSTS 1 año + preload, `frame-deny`, `nosniff`, `no-referrer`, permissions-policy bloqueado, `Cache-Control: no-store`.
- **jwtVerify**: algoritmo fijado (`algorithms:[HS512]`) → sin *algorithm confusion*/`alg:none`; valida `sub`/`jti`; expiración por librería.
- **fitness-service**: sin BOLA — todas las queries acotadas por `req.user.id`.

## 4. Estado y siguiente etapa

La **revisión de código del backend está completa**. El riesgo residual es **operacional**, fuera del alcance de una auditoría estática:

1. **Verificación de RLS en el Supabase desplegado** — el código define policies (`ENABLE ROW LEVEL SECURITY` + deny-all), pero `service_role` las bypasea por diseño. Confirmar que estén **activas en producción** y que la `anon key` no exponga tablas sensibles es un **pentest en vivo**.
2. **Config/secretos de Railway** — que `whsec_`/`sk_live_` sean correctos y que `INTER_SERVICE_SECRET` coincida entre servicios solo se valida en el entorno real.
3. **Frontend Flutter** — output-encoding en cualquier render HTML (WebView/panel), almacenamiento seguro de tokens (Keychain/Keystore), certificate pinning.

**Recomendación:** ejecutar (1) un checklist de verificación de RLS contra el Supabase real, y en paralelo iniciar (3) la auditoría del cliente Flutter (superficie distinta: almacenamiento local, deep links, WebViews).

---

*Generado como parte de la auditoría de seguridad ofensiva de GymPro. Todos los fixes están cubiertos por tests automatizados (unitarios + integración en CI).*
