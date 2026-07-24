# Remediación — Fase 1 (infraestructura, CI/CD y configuración)

> Rama: `security/fase-1-infra-cicd`. Alcance: hallazgos de Fase 1 del
> `audit-final-consolidado.md` que NO son de móvil. Metodología por hallazgo:
> baseline → corrección → validación → commit. Fecha: 2026-07-24.

| # | Hallazgo | Estado | Commit |
|---|----------|--------|--------|
| 1 | A02-1 `.dockerignore` en raíz | ✅ Corregido | `feat(sec): A02-1 …` |
| 2 | A02-2 borrar `.env.bak.*` | ✅ Corregido | `chore(sec): A02-2 …` |
| 3 | A03-1 `permissions:` en workflows | ✅ Corregido | `ci(sec): A03-1 …` |
| 4 | A03-2 pin de actions a SHA | ⏳ Pendiente aprobación | — |
| 5 | CLD-2 imagen base por digest | ⏳ Pendiente aprobación | — |
| 6 | CLD-5 Redis con `--requirepass` + puertos | ✅ Corregido | `fix(sec): CLD-5 …` |
| 7 | A04-2 eliminar `ENCRYPTION_KEY` muerta | ✅ Corregido | `refactor(sec): A04-2 …` |

*(los hashes de commit se anotan al final de cada sección tras confirmarse)*

---

## 1. A02-1 — `.dockerignore` en la raíz del contexto de build

**Estado:** ✅ Corregido

**Baseline / causa raíz.** El build usa `context: .` (raíz del monorepo, ver
`docker-compose.yml:25` y `railway/*.json`), pero el único `.dockerignore` estaba en
`services/.dockerignore`. Docker **solo** aplica el `.dockerignore` ubicado en la raíz
del contexto → el de `services/` nunca se aplicaba y `.env`/`.env.bak.*` entraban a la
capa builder (el stage `builder` hace `COPY services/<svc> …`).

**Corrección.** Se creó `./.dockerignore` en la raíz que excluye `**/.env`,
`**/.env.*`, `**/*.env.bak.*`, `node_modules`, tests, `apps/`, `docs/`, `.git`,
`.github`, etc., conservando lo que los Dockerfiles necesitan (`services/*/src`,
`services/*/package*.json`, `packages_shared`).

**Validación.** Simulación de matching de patrones (estilo Docker con `**`):
- Excluidos correctamente: `services/*/.env`, `.env.example`, `.env.bak.*`,
  `node_modules/**`, `tests/**`, `apps/**`, `docs/**`. ✅
- Conservados: `services/auth-service/package.json`, `package-lock.json`,
  `src/main.js`, `packages_shared/security/jwtVerify.js`. ✅

**Nota.** Se mantiene `services/.dockerignore` (inerte para `context: .`, sin daño);
la fuente de verdad ahora es el de la raíz.

**Commit:** `<pendiente de anotar>`
