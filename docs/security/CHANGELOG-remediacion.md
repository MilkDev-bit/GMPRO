# CHANGELOG — Remediación de seguridad (por rama)

> Formato estilo *Keep a Changelog* + *Conventional Commits*. IDs = hallazgos de
> `audit-final-consolidado.md`. Estado: F1 en `origin`; F2/F3 en working tree
> (git bloqueado en el entorno, ver comandos de commit en cada `remediation-*.md`).

---

## `security/fase-1-infra-cicd` — Infra / CI-CD / config (riesgo bajo) · en `origin`

### Security
- **A02-1** `feat`: añadido `./.dockerignore` en la raíz del contexto de build →
  `**/.env*` y `**/*.env.bak.*` ya no entran a la capa builder. `commit 7f19269`
- **A02-2** `chore`: neutralizados los `services/*/.env.bak.*` (vaciados; no tracked).
  *Pendiente:* `rm` de los inodos.
- **A03-1** `ci`: `permissions: contents: read` (mínimo privilegio) en los 4 workflows.
  `commit b11c6de`
- **CLD-2** `build`: imagen base pinneada por **digest** `node:22-alpine@sha256:968df3…`
  en los 5 Dockerfiles (15 líneas `FROM`). `commit 1690362`
- **CLD-5** `fix`: Redis con `--requirepass` y sin publicar el puerto interno en
  `docker-compose.yml`. `commit 4150c02`
- **A04-2** `refactor`: eliminada la variable muerta `ENCRYPTION_KEY` de auth-service.
  `commit ac88d0e`

### Changed
- **API9** `feat`: deprecación **no destructiva** de rutas legacy (headers RFC 8594
  `Deprecation`/`Sunset` + log `DEPRECATED_ROUTE_USED`) en access (`/generate-qr`,
  `/create-ticket`, `/validate-ticket`) y payment (`/api/v1/cash-payment`); nuevo
  `packages_shared/security/deprecation.js`. Rutas viejas siguen operativas. `commit aa1e2eb`

### Docs
- Informes de remediación (`remediation-fase1-infra.md`, `-api.md`) `commit df088e0`
  y auditorías OWASP (`audit-00…07`, `audit-final-consolidado.md`) `commit 04a20f1`.

### Pendiente (manual)
- **A03-2**: pinnear a SHA `subosito/flutter-action@v2` y `ruby/setup-ruby@v1`
  (4/6 resueltos; script en `remediation-fase1-infra.md §4`).
- **API3**: `select('*')` → `SAFE_COLUMNS` (requiere confirmar columnas en staging).

**Tests:** payment 30, access 8, auth 41 — verdes. `node --check` OK en todo.

---

## `security/fase-2-mediano` — Fail-closed / SCA / alertas / CSP (riesgo medio)

### Security
- **A10-1** `fix`: rate limiter **fail-closed**. Sin Redis en prod → 503 en el
  endpoint (no MemoryStore silencioso) con `/health` y `/ready` exentos; evento
  `RATE_LIMITER_STORE_UNAVAILABLE`; `passOnStoreError:false` explícito.
  *(`packages_shared/security/rateLimiter.js`)*
- **A09-3 / CLD-7** `feat`: exportación de eventos de seguridad a **Sentry**
  (credential-agnostic, no-op sin `SENTRY_DSN`) vía transport de winston que reenvía
  6 event codes ya redactados; nuevo `packages_shared/security/sentry.js`; evento
  `LOGIN_FAILED` añadido al 401 de `/login`. `@sentry/node` en `packages_shared`.
- **A08-2** `fix`: **CSP** restrictiva inyectada solo en build de producción
  (`vite.config.ts`) + **self-host de Inter** vía `@fontsource/inter` (retirado el
  CDN de Google Fonts).

### Added (CI)
- **A03-3/4 · CLD-3** `ci`: `.github/dependabot.yml` (npm ×7 + pub + github-actions +
  docker) y `.github/workflows/security-scan.yml` con OSV-Scanner, `npm audit`,
  **SBOM CycloneDX (Syft)** y **Trivy** de imágenes — todo en **report-only** (gate
  marcado con `GATE:` para activar tras el primer barrido).

### Pendiente (manual / credenciales)
- Cargar `SENTRY_DSN` (Railway + CI), `npm install @sentry/node`, crear 3 reglas de
  alerta. `npm install` + build/preview del panel y revisión de consola (CSP).
  Activar el gate de `security-scan.yml`. Pinnear sus actions a SHA.

**Tests:** A10-1 → 4 tests; regresión auth **45 passed**. `node --check` OK.

---

## `security/fase-3-estructural` — JWT / roles BD / SSRF / threat model / iOS (mayor riesgo)

### Security
- **A04-1 / CLD-4** `feat`: **JWT asimétrico (RS256/EdDSA) con convivencia**.
  `jwtVerify.verifyToken()` acepta clave **pública** nueva y **secreto** viejo hasta
  que expiren los tokens (anti-confusión RS/HS, anti `alg:none`); firma asimétrica en
  `tokenService` si hay `JWT_PRIVATE_KEY`, si no HS* → **sin invalidar tokens de
  golpe**. `environment.js` exporta `JWT_PRIVATE_KEY`/`JWT_SIGN_ALGORITHM`.
- **A01-3** `feat`: guard **anti-SSRF cableado** en
  `services/ai-service/src/services/safeImageFetch.js` (`fetchUserImage`), vía
  obligatoria para URLs de usuario (bloquea loopback/RFC1918/metadata/IPv6/
  credenciales, https-only, no-redirect, tipo/tamaño). *(No hay endpoint de URL de
  usuario hoy; listo para el flujo multimodal.)*

### Added (propuesta / diseño)
- **CLD-1** `feat` (propuesta, **no ejecutada**): `009_least_privilege_roles.sql` —
  roles `svc_*` de mínimo privilegio + GRANTs + policies RLS por servicio. Requiere
  ejecución manual en Supabase (ver **riesgos** en `PR-DESCRIPTION-consolidado.md §3`).
- **A06-1** `docs`: `docs/security/threat-model.md` (DFD + STRIDE de pago, acceso
  físico, identidad, IA/PII).
- **IOS-4** `docs`: diseño + snippet de OAuth por `ASWebAuthenticationSession` /
  Universal Links + plan de transición (sin compilar; requiere release en store).

### Pendiente (manual)
- Generar par de claves JWT y rotar (distribuir pública → activar privada en auth →
  retirar `JWT_SECRET`). Aplicar la migración 009 en staging→prod (canary). Implementar
  y publicar el flujo OAuth iOS.

**Tests:** A04-1 → 5 tests; A01-3 → 39 tests (con el suite SSRF existente); regresión
auth **50 passed**. `node --check` OK; SQL 009 con paréntesis balanceados en sentencias.

---

## Resumen de validación por fase

| Rama | Corregido+tested | Diseño/manual | Estado git |
|------|------------------|---------------|------------|
| fase-1-infra-cicd | infra/CI/API9 (79 tests backend verdes) | A03-2, API3 | en `origin` |
| fase-2-mediano | A10-1 (4), auth 45 | Sentry DSN, CSP browser, gate CI | working tree |
| fase-3-estructural | A04-1 (5), A01-3 (39), auth 50 | roles BD, iOS, threat model | working tree |
