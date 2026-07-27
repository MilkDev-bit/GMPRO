# Audit 01 — Backend/API/Web · A01 Acceso · A02 Configuración · A03 Cadena de suministro

> Alcance: backend (5 microservicios Node/Express + `packages_shared/security`) y
> frontend web (`apps/admin-web`). Basado en `audit-00-mapeo.md`. Estándar de
> referencia: OWASP Top 10:2025. Fecha: 2026-07-24.
> Método: revisión de código estático con evidencia `archivo:línea`. No se
> inventan hallazgos; las limitaciones (sin acceso a red/consola cloud/logs) se
> indican explícitamente.

## Tabla resumen

| ID | Categoría | Hallazgo | Severidad | Evidencia |
|----|-----------|----------|-----------|-----------|
| A01-1 | Control de acceso | RBAC + verificación JWT robusta (whitelist de alg, claims, blacklist) | ✅ Correcto | `packages_shared/security/jwtVerify.js` |
| A01-2 | Control de acceso | Autorización a nivel de objeto (anti-IDOR) en recibos y rutinas | ✅ Correcto | `paymentController.js` getReceiptPdf; `routineController.js:71` |
| A01-3 | SSRF | `ssrfGuard` sólido pero **no cableado**; hoy ninguna URL de usuario llega a un fetch server-side | Baja (latente) | `ssrfGuard.js`; usos solo en `tests/` |
| A02-1 | Misconfiguración | **`.dockerignore` mal ubicado**: el context de build es la raíz, el ignore está en `services/` → no se aplica; `.env`/`.env.bak.*` entran a la capa builder | **Media** | `docker-compose.yml:25` (`context: .`); solo existe `services/.dockerignore` |
| A02-2 | Misconfiguración | `.env` reales y `.env.bak.*` con secretos en el working tree (gitignored, no tracked) | Baja | `services/*/.env.bak.*`; `.gitignore:6,87` |
| A02-3 | Misconfiguración | Cabeceras/Helmet/HSTS/CORS/errorHandler bien configurados; Dockerfiles non-root | ✅ Correcto | `helmetConfig.js`; `errorHandler.js:21`; `Dockerfile:31` |
| A02-4 | Misconfiguración | Config de producción (Railway) no verificable desde el repo | Info (pendiente) | `railway/*.json` |
| A03-1 | Cadena suministro | Workflows CI **sin bloque `permissions:`** → GITHUB_TOKEN con permisos por defecto | **Media** | `.github/workflows/*.yml` (ausencia) |
| A03-2 | Cadena suministro | Actions de terceros **pinneadas a tags mutables** (`@v2`,`@v1`) no a SHA | **Media** | `android-release.yml:34,40`; `ios-release.yml:21,27` |
| A03-3 | Cadena suministro | **Sin SCA/escaneo** (npm audit, Dependabot, Renovate, CodeQL, Trivy) | **Media** | `.github/`, `scripts/` (ausencia) |
| A03-4 | Cadena suministro | Sin generación de **SBOM** | Baja | (ausencia) |
| A03-5 | Cadena suministro | Lockfiles presentes + `npm ci --frozen-lockfile` (builds reproducibles) | ✅ Correcto | `services/*/package-lock.json`; `Dockerfile:9` |

**Limitación global:** `npm audit` no se pudo ejecutar (la allowlist de red del
entorno bloquea el registry). El estado real de vulnerabilidades conocidas en
dependencias queda **sin determinar**; debe correrse en una máquina de CI/dev con
acceso a `registry.npmjs.org`.

---

## A01 — Control de acceso roto (incl. SSRF) · Severidad global: Baja

### Evidencia — controles correctos

**Verificación JWT (whitelist de algoritmo, claims obligatorios, blacklist).**
`packages_shared/security/jwtVerify.js`: `jwt.verify(token, JWT_SECRET, { algorithms: [JWT_ALGORITHM] })` rechaza `alg:none`; valida `sub`+`jti`; consulta blacklist en Redis (`jwt:blacklist:<jti>`); RBAC por `requiredRoles.includes(decoded.role)` → 403. Autenticación M2M con `timingSafeEqual` (`jwtVerify.js:165-200`).

**Autorización a nivel de objeto (anti-IDOR/BOLA).**
- Recibos PDF: `paymentController.getReceiptPdf` comprueba
  `req.user.id !== subscription.usuario_id && req.user.role !== 'admin'` → **403**.
- Rutinas: `routineController.deleteRoutine` delega en
  `routineModel.deleteRoutine(id, usuarioId)` (borrado **scoped por `usuario_id`**);
  404 si no pertenece al usuario (`routineController.js:71-79`).
- Rutas admin (`/admin/*` en auth y payment) exigen `requiredRoles: STAFF_ROLES`
  server-side (verificado en `audit-01`/tests: miembro→403, staff/admin→200).

**Frontend web.** El gating por rol de `admin-web` (ingresos solo admin) es de UX;
la autorización **real** la impone el backend (RBAC en las rutas admin). Correcto.

### Evidencia — SSRF (hallazgo A01-3, Baja/latente)
`packages_shared/security/ssrfGuard.js` es completo (bloquea loopback, privadas,
link-local `169.254.169.254`, CGNAT, IPv6 ULA/mapeadas; valida todas las IPs de
DNS; `redirect:'error'`). **Pero solo se referencia en
`services/ai-service/tests/ssrfGuard.test.js`** — nunca en código de producción.

Se revisaron todas las llamadas salientes (`grep axios|fetch`): son a destinos
**fijos o internos** (LLM APIs, Open Food Facts con `barcode` saneado por
`normalizeBarcode` → `replace(/\D/g,'')`, servicios internos). **Ninguna usa una
URL provista por el usuario**, por lo que hoy no hay vector SSRF explotable.

- **Impacto:** nulo hoy; alto si se añade la función de "análisis de imagen por URL"
  (mencionada en el docstring del guard) sin cablear el guard.
- **Remediación:** al introducir cualquier endpoint que acepte una URL de usuario
  para fetch server-side, envolver con `assertSafePublicUrl`/`safeFetch`. Añadir un
  test de regresión que falle si un `fetch` nuevo recibe input de usuario sin guard.

### Qué faltaría revisar
Inventario exhaustivo de rutas de los 5 servicios (aquí se auditaron los endpoints
de mayor riesgo). Recomendado: generar la lista completa de rutas y confirmar
`usuario_id`-scoping en cada `GET/PUT/DELETE /:id` de access/fitness/ai.

---

## A02 — Mala configuración de seguridad · Severidad global: Media

### A02-1 (Media) — `.dockerignore` no se aplica al context de build
**Evidencia:** `docker-compose.yml:25` define `context: .` (raíz del monorepo) con
`dockerfile: services/auth-service/Dockerfile`. El único ignore es
`services/.dockerignore`. **Docker solo lee el `.dockerignore` en la raíz del
context** (`./.dockerignore`, inexistente), por lo que `services/.dockerignore`
**se ignora**. El stage builder hace `COPY services/auth-service ./services/auth-service`
(`auth-service/Dockerfile:14`), copiando `.env`, `.env.bak.*`, `node_modules` y
tests a la **capa intermedia** del build.

- **Impacto:** la imagen final NO incluye `.env` (producción solo copia `src` +
  `package.json`), pero los **secretos quedan en capas/caché del builder**; si se
  publican imágenes multi-stage completas o se comparte la caché de build, se
  filtran `JWT_SECRET`, claves Supabase/Stripe, etc.
- **Remediación:** crear **`./.dockerignore` en la raíz** del repo con al menos
  `**/.env`, `**/.env.*`, `!**/.env.example`, `**/node_modules`, `**/*.test.js`,
  `.git`, `docs/`. Verificar con `docker build --no-cache` que la capa builder ya
  no contiene `.env` (`docker history` / `dive`).

### A02-2 (Baja) — `.env` y `.env.bak.*` con secretos en el working tree
**Evidencia:** existen `services/*/.env` y `services/*/.env.bak.20260721*` en disco.
`git ls-files` confirma que **no están versionados** (solo `.env.example`); el
`.gitignore` los cubre (`.gitignore:6` `.env`, `:87` `*.env.bak.*`).
- **Impacto:** no hay fuga por git, pero los `.bak` con secretos reales persisten en
  la máquina y entran al context de build (ver A02-1); riesgo de backup/robo local.
- **Remediación:** eliminar los `.env.bak.*` tras usarlos (`sync-secrets.sh`);
  confirmar rotación de cualquier secreto que haya estado en un `.bak`.

### A02-4 (Info) — Configuración de producción no verificable desde el repo
`railway/*.json` define despliegue, pero los **valores** de variables y la
exposición de red/Redis en producción no son auditables desde el código.
- **Qué necesitaría:** acceso a la consola de Railway (variables por servicio,
  visibilidad pública de Redis, `NODE_ENV=production` efectivo, dominios/CORS reales).

### Evidencia — controles correctos (A02-3)
- **Helmet** maximalista para API: CSP `default-src 'none'` y todo en `'none'`
  (`helmetConfig.js:44-60`), HSTS 1 año `includeSubDomains; preload`
  (`:85-89`), COOP/COEP/CORP, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`,
  Permissions-Policy restrictiva, `X-Powered-By` eliminado; `Cache-Control: no-store`
  para respuestas de API (`:160`).
- **errorHandler** no expone stack en producción (`errorHandler.js:21`
  `isProduction`); mapeo controlado de errores (validación, JWT, CORS, DB, Stripe).
- **Dockerfiles**: `node:22-alpine`, multi-stage, `USER node` (non-root,
  `Dockerfile:31`), `dumb-init`, `HEALTHCHECK`, `npm ci --omit=dev`.
- **`trust proxy` = 1** en los 5 servicios (rate limiting fiable tras el proxy de
  Railway) — `access/ai/auth/fitness/payment main.js`.
- **CORS**: lista explícita de orígenes, nunca `*` con `credentials`
  (`corsConfig.js:126-150`). Nota menor: `validateOrigin` permite requests **sin**
  header `Origin` (clientes no-browser); aceptable y documentado.

---

## A03 — Fallos en la cadena de suministro · Severidad global: Media

### A03-1 (Media) — Workflows sin `permissions:` (token sobre-privilegiado)
**Evidencia:** ninguno de `.github/workflows/{test,integration,android-release,ios-release}.yml`
declara bloque `permissions:` (grep sin resultados). El `GITHUB_TOKEN` toma los
**permisos por defecto del repo** (potencialmente read/write).
- **Impacto:** un step/acción comprometida podría escribir en el repo, releases o
  packages. Crítico en los workflows de release, que manejan secretos de firma.
- **Remediación:** añadir en cada workflow `permissions: contents: read` a nivel
  top y elevar por-job solo lo imprescindible (p. ej. `contents: write` para subir
  artefactos de release).

### A03-2 (Media) — Actions de terceros pinneadas a tags mutables
**Evidencia:** `subosito/flutter-action@v2` (`android-release.yml:34`,
`ios-release.yml:21`), `ruby/setup-ruby@v1` (`android-release.yml:40`,
`ios-release.yml:27`), además de `actions/*@v4`. Los tags son **mutables**.
- **Impacto:** si un tag de una action de terceros es reescrito/comprometido, se
  ejecuta código arbitrario en los pipelines de release **con acceso a keystore,
  certificados y API keys de las stores**.
- **Remediación:** pinnear a **SHA de commit completo** (`uses: owner/action@<sha> # vX.Y`).
  Priorizar las actions de terceros; habilitar la política "pin actions to SHA".

### A03-3 (Media) — Sin análisis de composición de software (SCA)
**Evidencia:** no hay `npm audit`, Dependabot (`.github/dependabot.yml` ausente),
Renovate, Snyk, Trivy, CodeQL ni OSV en `.github/` ni en `scripts/`
(`scripts/check-secrets.sh` solo compara coherencia de secretos, no escanea).
- **Impacto:** las dependencias vulnerables no se detectan ni se bloquean; sin
  alertas de actualización.
- **Remediación:** (a) añadir `.github/dependabot.yml` (ecosistemas npm por servicio
  + pub + github-actions); (b) step de CI `npm audit --omit=dev --audit-level=high`
  (o `osv-scanner`) que falle el build; (c) considerar CodeQL para SAST.

### A03-4 (Baja) — Sin SBOM
- **Impacto:** trazabilidad limitada ante un CVE en la cadena (no hay inventario
  firmado de componentes).
- **Remediación:** generar CycloneDX en CI (`@cyclonedx/cyclonedx-npm` por servicio;
  para Flutter, `cyclonedx` de pub) y adjuntarlo a los releases.

### Evidencia — controles correctos (A03-5)
Lockfiles presentes en los 5 servicios (`package-lock.json`) y `pubspec.lock` en la
app; los Dockerfiles instalan con `npm ci --omit=dev --frozen-lockfile`
(`Dockerfile:9`) → instalaciones **reproducibles** y sin devDependencies en imagen.

### Limitación
No fue posible ejecutar `npm audit` (registry bloqueado por la allowlist del
entorno: `403 … Connection blocked by network allowlist`). **Acción requerida:**
correr `npm audit` / `osv-scanner` por servicio en CI o en una máquina con acceso a
`registry.npmjs.org` para determinar el estado real de CVEs en dependencias.

---

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Crear `./.dockerignore` en la raíz (excluir `**/.env*`) | A02-1 |
| 2 | Añadir `permissions: contents: read` a los 4 workflows | A03-1 |
| 3 | Pinnear actions de terceros a SHA (release pipelines) | A03-2 |
| 4 | Dependabot + `npm audit`/OSV en CI (gate) | A03-3 |
| 5 | Borrar `.env.bak.*` y confirmar rotación | A02-2 |
| 6 | SBOM (CycloneDX) en releases | A03-4 |
| 7 | Cablear `ssrfGuard` si se añade fetch de URL de usuario | A01-3 |
| — | Ejecutar `npm audit` real (fuera del sandbox) | Limitación |
| — | Revisar variables/red en consola Railway | A02-4 |
