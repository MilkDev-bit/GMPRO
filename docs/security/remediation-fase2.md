# Remediación — Fase 2 (mediano plazo)

> Rama objetivo: `security/fase-2-mediano`. Cubre A10-1, A03-3/A03-4/CLD-3,
> A09-3/CLD-7 y A08-2 del `audit-final-consolidado.md`. Fecha: 2026-07-24.
> Fase 1 confirmada completada y en `origin/security/fase-1-infra-cicd` (7 commits
> `(sec)` + docs, HEAD `04a20f1`).

## ⚠ Restricción del entorno
El FS montado bloquea `unlink` de `.git/*.lock` → **no se pudo crear la rama ni
commitear** aquí; los cambios están **aplicados y validados en el working tree**.
```bash
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null
git checkout -b security/fase-2-mediano
# … luego el "Comando de commit" del final.
```
Además, sin toolchain de Flutter/npm-install en el entorno, la validación de
**build del panel y navegador** queda como *pendiente manual* (indicado abajo).

## Estado

| # | Hallazgo | Estado |
|---|----------|--------|
| 1 | A10-1 rate limiter fail-closed | ✅ Corregido + **4 tests verdes** |
| 2 | A03-3/A03-4/CLD-3 SCA/SBOM/imágenes | ✅ Automatizado (report-only) · ⏳ `npm install` + activar gate |
| 3 | A09-3/CLD-7 detección/alertas (Sentry) | ✅ Integrado (env-based) · ⏳ **tú**: crear reglas de alerta + set `SENTRY_DSN` |
| 4 | A08-2 CSP + self-host fuente | ✅ Corregido · ⏳ validación en navegador (build) |

---

## 1. A10-1 — Rate limiter fail-closed
**Archivo:** `packages_shared/security/rateLimiter.js` (+ test
`services/auth-service/tests/rateLimiterFailClosed.test.js`).

**Baseline.** `express-rate-limit` v7 **ya trae `passOnStoreError: false` por
defecto** → un error de Redis en runtime ya era fail-closed. El hueco real era el
**fallback silencioso a MemoryStore cuando no había Redis** (fail-open entre réplicas).

**Corrección.**
- Nueva fábrica `makeLimiter()`: en **producción sin Redis** NO cae a MemoryStore;
  devuelve un middleware **fail-closed** que responde **503** en el endpoint afectado
  y **exime `/health` y `/ready`** (el servicio sigue vivo, no es un apagón total).
- Emite el evento **`RATE_LIMITER_STORE_UNAVAILABLE`** (logger.error, throttled 1/30s)
  → visible para alerta (enganchado a Sentry, punto 3). No es un apagón silencioso.
- `passOnStoreError: false` **explícito** en todos los limitadores (runtime fail-closed).
- En **desarrollo** sin Redis se mantiene MemoryStore (cómodo, una sola instancia).

**Tests (verdes):** producción sin Redis → 503 y `/health` 200 (servicio vivo);
`/ready` exento; desarrollo → MemoryStore aplica el límite (429 al superarlo); error de
store en runtime con `passOnStoreError:false` → request bloqueada (no 200) sin crash.
Regresión de auth intacta (**45 passed**).

**Commit:** `git add packages_shared/security/rateLimiter.js services/auth-service/tests/rateLimiterFailClosed.test.js`

---

## 2. A03-3 / A03-4 / CLD-3 — SCA, SBOM y escaneo de imágenes
**Archivos:** `.github/dependabot.yml`, `.github/workflows/security-scan.yml`.

**Política anti-ruptura (cumplida):** TODO arranca en **report-only** — no rompe el
pipeline aunque haya CVEs preexistentes sin parche. Se revisa el backlog primero; el
**gate bloqueante** se activa después (marcado con comentarios `GATE:` en el workflow).

**Automatizado:**
- **Dependabot** (`dependabot.yml`): auto-PRs semanales para los 5 servicios npm,
  `packages_shared`, `admin-web`, la app **Flutter (pub)**, **github-actions** (mantiene
  los pins de A03-2) y **docker** (mantiene el digest de CLD-2).
- **SCA**: job `sca-osv` (OSV-Scanner recursivo → SARIF a Security tab, `continue-on-error`)
  + job `npm-audit` por servicio (`--audit-level=high`, report-only).
- **SBOM**: job `sbom` con **Syft → CycloneDX JSON** por componente, subido como
  artefacto (y adjuntado al release cuando el evento es `release`).
- **Imágenes**: job `image-scan` (**Trivy**) que construye cada imagen y la escanea
  (`HIGH,CRITICAL`, `exit-code: 0` = report). Solo en `workflow_dispatch`/tags para no
  construir 5 imágenes en cada push.

**⏳ Pendiente:**
- Los nuevos steps usan **acciones con tag** (`@v4`, `@v1`, `@0.28.0`…) marcadas con
  `# TODO A03-2: pin a SHA` — pinnearlas junto con las 2 de la Fase 1 (mismo backlog A03-2).
- **Activar el gate**: tras revisar el primer barrido, quitar `continue-on-error` /
  poner `exit-code: "1"` / `--audit-level` estricto (indicado en el workflow).
- Requiere que el repo tenga **Code scanning** habilitado para ver los SARIF.

---

## 3. A09-3 / CLD-7 — Detección y alertas (Sentry)
**Archivos:** `packages_shared/security/sentry.js` (nuevo), `packages_shared/security/logger.js`
(engancha el transport), `packages_shared/package.json` (`@sentry/node`),
`services/auth-service/src/controllers/authController.js` (evento `LOGIN_FAILED`).

**Integración (credential-agnostic — confirmaste que TIENES DSN):**
- `sentry.js` inicializa Sentry **solo si `SENTRY_DSN` está en el entorno** (no-op y sin
  dependencia en runtime si falta; degrada sin crashear si el paquete no está).
- Un **transport de winston** reenvía a Sentry SOLO los logs cuyo `event ∈` conjunto de
  alertas: `WEBHOOK_SIGNATURE_INVALID`, `INTER_SERVICE_AUTH_FAILED`, `LOGIN_FAILED`,
  `RATE_LIMITER_STORE_UNAVAILABLE`, `JWT_BLACKLISTED`, `INSUFFICIENT_ROLE`.
- El redactado de secretos ocurre **antes** de los transports → a Sentry llegan datos
  ya redactados (sin secretos/PII). `sendDefaultPii: false`, `tracesSampleRate: 0`.
- Se añadió el evento **`LOGIN_FAILED`** en el 401 de `/login` (sin email completo, solo
  el dominio) para poder detectar **ráfagas de 401**.

**Validación:** `node --check` OK; suite de auth **45 passed** con el transport activo
(no-op sin DSN). La entrega real a Sentry es *pendiente* (requiere `@sentry/node`
instalado + `SENTRY_DSN`).

**🔷 QUÉ NECESITO DE TI:**
1. **`npm install`** en `packages_shared` (ya añadí `@sentry/node` al `package.json`).
2. Poner **`SENTRY_DSN`** (y opcional `SENTRY_RELEASE`) como variable de entorno en cada
   servicio (Railway). Sin ella, todo queda no-op y seguro.
3. Crear en Sentry estas **3 reglas de alerta** (Alerts → Create Alert → "Number of events"):
   - **Firma de webhook inválida:** `event.tag event = WEBHOOK_SIGNATURE_INVALID`,
     umbral p. ej. **≥1 en 5 min** → notifica al canal de seguridad.
   - **Fallo de auth M2M:** `event = INTER_SERVICE_AUTH_FAILED`, **≥1 en 5 min**.
   - **Ráfaga de 401 en /login:** `event = LOGIN_FAILED`, **> N en M min** (p. ej.
     **>20 en 5 min**) → posible fuerza bruta. (Complementa al lockout por cuenta.)
   - (Sugeridas) `RATE_LIMITER_STORE_UNAVAILABLE` (≥1 → Redis caído) y `JWT_BLACKLISTED`.

---

## 4. A08-2 — CSP en la SPA + self-host de la fuente
**Archivos:** `apps/admin-web/vite.config.ts` (CSP), `src/main.tsx` + `src/index.css`
(fuente), `package.json` (`@fontsource/inter`).

**Corrección.**
- **Self-host de Inter:** se elimina `@import url(fonts.googleapis.com…)` de `index.css`
  y se importa **`@fontsource/inter`** (400–800) en `main.tsx` → cero dependencia de un
  origen de terceros (verificado: sin referencias a `fonts.googleapis`/`gstatic`).
- **CSP restrictiva** inyectada como `<meta http-equiv>` **solo en el build de
  producción** (plugin `cspMetaPlugin`, gate `command === 'build'`), para **no romper el
  HMR de `vite dev`** (que necesita inline/eval/ws). Política:
  `default-src 'self'; object-src 'none'; frame-ancestors 'none'; img-src 'self' data:;
  font-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self';
  connect-src 'self' https://*.up.railway.app; form-action 'self'; base-uri 'self'`.

**⏳ Pendiente (validación que no puedo ejecutar aquí):**
- `npm install` (para `@fontsource/inter`) y **`npm run build && npm run preview`**;
  abrir el panel y revisar la **consola del navegador** por bloqueos CSP inesperados
  (login, dashboard con Recharts, navegación). Si Recharts generara algún bloqueo de
  estilo, ya está contemplado con `style-src 'unsafe-inline'`.
- Fijar la CSP **también como cabecera HTTP** en el host estático (defensa en
  profundidad; el `<meta>` no cubre algunas directivas como `frame-ancestors` en todos
  los navegadores). Si migran de `*.up.railway.app` a dominio propio, actualizar
  `connect-src`.

---

## Validación: hecho vs pendiente

| Punto | Automático (hecho) | Pendiente |
|-------|--------------------|-----------|
| A10-1 | ✅ 4 tests jest + regresión 45 passed | — |
| A03-3/4/CLD-3 | ✅ YAML válido (dependabot + workflow) | `npm install`; primer barrido; activar gate; pin SHA |
| A09-3/CLD-7 | ✅ node --check + auth 45 passed (no-op) | `npm install @sentry/node`; `SENTRY_DSN`; crear reglas de alerta |
| A08-2 | ✅ estático (sin CDN, CSP build-only, balance) | `npm install`; build + revisión en navegador; CSP como header |

## Comando de commit
```bash
git add packages_shared/security/rateLimiter.js \
        packages_shared/security/sentry.js \
        packages_shared/security/logger.js \
        packages_shared/package.json \
        services/auth-service/src/controllers/authController.js \
        services/auth-service/tests/rateLimiterFailClosed.test.js \
        .github/dependabot.yml .github/workflows/security-scan.yml \
        apps/admin-web/vite.config.ts apps/admin-web/src/main.tsx \
        apps/admin-web/src/index.css apps/admin-web/package.json \
        docs/security/remediation-fase2.md
git commit -m "feat(sec): Fase 2 — rate limiter fail-closed, SCA/SBOM/image scan (report-only), Sentry alerts, SPA CSP + self-host font"
```
