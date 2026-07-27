# Remediación — Fase 1 (infraestructura, CI/CD y configuración)

> Rama: `security/fase-1-infra-cicd`. Alcance: hallazgos de Fase 1 del
> `audit-final-consolidado.md` que NO son de móvil. Metodología por hallazgo:
> baseline → corrección → validación → commit. Fecha: 2026-07-24.

## ⚠ Restricción del entorno de trabajo (leer primero)
El sistema de archivos montado **bloquea el `unlink`** de ciertos archivos
(`Operation not permitted`): esto impidió (a) borrar los inodos de los `.env.bak.*`
y (b) eliminar los `.git/*.lock` que git deja tras un commit. Consecuencia:
- **Solo el primer commit (A02-1) pudo aterrizar** (`7f19269`). Tras él, quedaron
  `.git/index.lock` y `.git/HEAD.lock` no eliminables → los commits siguientes se
  bloquean **en este entorno**.
- El resto de correcciones **están aplicadas y validadas en el working tree**; solo
  falta **empaquetarlas en commits**, lo que se hace en un entorno sin la restricción:

```bash
# En una máquina/entorno normal, desde la raíz del repo y en la rama:
git checkout security/fase-1-infra-cicd
rm -f .git/index.lock .git/HEAD.lock         # limpiar locks huérfanos
# luego ejecutar los "Comando de commit" de cada sección de abajo.
```

## Estado

| # | Hallazgo | Estado | Commit |
|---|----------|--------|--------|
| 1 | A02-1 `.dockerignore` en raíz | ✅ Corregido **y commiteado** | `7f19269` |
| 2 | A02-2 borrar `.env.bak.*` | ✅ Secretos eliminados (contenido) · ⏳ `rm` de inodos manual | (sin delta git) |
| 3 | A03-1 `permissions:` en workflows | ✅ Corregido en árbol · ⏳ commit | pendiente |
| 4 | A03-2 pin de actions a SHA | ⏳ Pendiente aprobación (4/6 resueltos) | pendiente |
| 5 | CLD-2 imagen base por digest | ✅ Corregido en árbol · ⏳ commit | pendiente |
| 6 | CLD-5 Redis `--requirepass` + puertos | ✅ Corregido en árbol · ⏳ commit | pendiente |
| 7 | A04-2 eliminar `ENCRYPTION_KEY` muerta | ✅ Corregido en árbol · ⏳ commit | pendiente |

---

## 1. A02-1 — `.dockerignore` en la raíz del contexto de build
**Estado:** ✅ Corregido y **commiteado** (`7f19269`).

**Causa raíz.** Build con `context: .` (raíz) pero el `.dockerignore` vivía en
`services/`; Docker solo aplica el de la raíz del contexto → `.env`/`.env.bak.*`
entraban a la capa builder.

**Corrección.** Nuevo `./.dockerignore` que excluye `**/.env`, `**/.env.*`,
`**/*.env.bak.*`, `node_modules`, tests, `apps/`, `docs/`, `.git`, `.github`,
conservando `services/*/src`, `services/*/package*.json` y `packages_shared`.

**Validación.** Simulación de matching estilo Docker (con `**`): excluye
`.env`/`.env.bak`/`node_modules`/`tests`/`apps`/`docs`; conserva `package.json`,
`package-lock.json`, `src/main.js`, `packages_shared/**`. ✅

---

## 2. A02-2 — Eliminar `.env.bak.*`
**Estado:** ✅ Material secreto eliminado · ⏳ borrado del inodo pendiente (manual).

**Confirmación previa (requerida por el encargo).** Los `.env.bak.*` **NO están
versionados** (`git ls-files` = 0) ni en el history (búsqueda por nombre = 0). Solo
existían en disco (10 archivos con secretos reales).

**Corrección.** Al no poder `rm` (restricción del entorno), se **truncaron a 0 bytes**
los 10 archivos → **se eliminó todo el material secreto** (verificado: `grep` de
`secret|key|password|sk_|whsec_|sb_secret|eyJ` = 0). El `.gitignore` ya los cubre
(`.gitignore:87 *.env.bak.*`), así que no hay delta en git.

**Pendiente (acción manual trivial):**
```bash
rm -f services/*/.env.bak.*
```
**Nota de riesgo residual:** aunque estos `.bak` nunca estuvieron en git, cualquier
secreto que hayan contenido debe considerarse **potencialmente expuesto** → ver Fase 3
(rotación de secretos) del plan consolidado.

---

## 3. A03-1 — `permissions:` de mínimo privilegio en workflows
**Estado:** ✅ Corregido en árbol · ⏳ commit pendiente.

**Corrección.** Se añadió `permissions:\n  contents: read` a nivel top-level en los 4
workflows (`test.yml`, `integration.yml`, `android-release.yml`, `ios-release.yml`).
Es el mínimo suficiente: solo hacen checkout/tests/build/`upload-artifact`; ninguno
crea GitHub Releases ni hace push (no requieren `contents: write` ni otros scopes).

**Validación.** Parseo YAML de los 4 → OK, `permissions={'contents':'read'}` en cada uno.

**Comando de commit:**
```bash
git add .github/workflows/{test,integration,android-release,ios-release}.yml
git commit -m "ci(sec): A03-1 add least-privilege permissions (contents: read) to workflows"
```

---

## 4. A03-2 — Pin de GitHub Actions a SHA de commit
**Estado:** ⏳ Pendiente aprobación (4 de 6 SHAs resueltos en la auditoría).

**Motivo de no aplicar automáticamente.** Fijar a un SHA **incorrecto** rompe el CI y
es un anti-patrón; por eso **no se inventa** ningún hash. Se resolvieron vía la API de
GitHub los SHA reales de 4 actions; 2 no respondieron en este entorno (intermitencia
del fetch). Para no dejar workflows medio-pinneados, no se editaron los archivos: se
aplican todos juntos con el script de abajo.

**SHAs resueltos (GitHub API, 2026-07-24 — verificar antes de merge):**

| Action | Tag | SHA de commit |
|--------|-----|---------------|
| `actions/checkout` | v4 | `34e114876b0b11c390a56381ad16ebd13914f8d5` |
| `actions/setup-node` | v4 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/setup-java` | v4 | `c1e323688fd81a25caa38c78aa6df2d33d3e20d9` |
| `actions/upload-artifact` | v4 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `subosito/flutter-action` | v2 | **pendiente de resolver** |
| `ruby/setup-ruby` | v1 | **pendiente de resolver** |

**Cómo completar (resuelve las 6 y reescribe los workflows; requiere `gh` autenticado
para evitar el rate-limit sin auth):**
```bash
pin() { # uso: pin owner/repo tag
  gh api "repos/$1/git/ref/tags/$2" -q '.object.sha'
}
CHECKOUT=$(pin actions/checkout v4)
NODE=$(pin actions/setup-node v4)
JAVA=$(pin actions/setup-java v4)
ARTIFACT=$(pin actions/upload-artifact v4)
FLUTTER=$(pin subosito/flutter-action v2)
RUBY=$(pin ruby/setup-ruby v1)
cd .github/workflows
sed -i "s|actions/checkout@v4|actions/checkout@${CHECKOUT} # v4|g"          *.yml
sed -i "s|actions/setup-node@v4|actions/setup-node@${NODE} # v4|g"          *.yml
sed -i "s|actions/setup-java@v4|actions/setup-java@${JAVA} # v4|g"          *.yml
sed -i "s|actions/upload-artifact@v4|actions/upload-artifact@${ARTIFACT} # v4|g" *.yml
sed -i "s|subosito/flutter-action@v2|subosito/flutter-action@${FLUTTER} # v2|g"  *.yml
sed -i "s|ruby/setup-ruby@v1|ruby/setup-ruby@${RUBY} # v1|g"                *.yml
```
> Recomendación: habilitar **Dependabot** con `package-ecosystem: github-actions`
> para actualizar estos digests de forma controlada (evita quedar en un SHA viejo).

---

## 5. CLD-2 — Imagen base por digest
**Estado:** ✅ Corregido en árbol · ⏳ commit pendiente.

**Corrección.** Los 5 Dockerfiles pasan de `FROM node:22-alpine` (tag mutable) a
`FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920`
en los 3 stages (deps/builder/production) = 15 líneas `FROM`.

**Origen del digest.** Manifest multi-arch (OCI image index) del tag `22-alpine`
obtenido de Docker Hub (`hub.docker.com/v2/repositories/library/node/tags/22-alpine`,
campo `digest`, 2026-05-14). Pinnear al índice permite que Docker resuelva la arch.

**Validación.** `grep` confirma 15/15 líneas con `@sha256:` y 0 sin digest.

**Comando de commit:**
```bash
git add services/*/Dockerfile
git commit -m "build(sec): CLD-2 pin node base image by digest (sha256:968df39…)"
```

---

## 6. CLD-5 — Redis con `--requirepass` y sin puertos internos publicados
**Estado:** ✅ Corregido en árbol · ⏳ commit pendiente.

**Corrección (docker-compose.yml).**
- Redis: `ports: ["6379:6379"]` → **`expose: ["6379"]`** (accesible solo en la red
  interna `gympro-network`, no publicado al host).
- `command: … --requirepass ${REDIS_PASSWORD:?define REDIS_PASSWORD}` (auth obligatoria).
- `healthcheck` con `redis-cli --no-auth-warning -a ${REDIS_PASSWORD} ping`.
- `REDIS_URL` de fitness/ai → `redis://:${REDIS_PASSWORD:?…}@redis:6379`.
- La BD (Supabase) es externa/cloud, no se publica desde compose (nada que cerrar).

**Validación.** Parseo YAML: `redis.ports=None`, `expose=['6379']`, `--requirepass`
presente, `REDIS_URL` con credenciales, y **ningún** `6379` publicado al host. ✅

**Requisito operativo:** definir `REDIS_PASSWORD` en el entorno/.env raíz antes de
`docker compose up` (el `:?` hace fallar el arranque si falta, por diseño).

**Comando de commit:**
```bash
git add docker-compose.yml
git commit -m "fix(sec): CLD-5 require Redis auth and stop publishing internal port"
```

---

## 7. A04-2 — Eliminar `ENCRYPTION_KEY` muerta
**Estado:** ✅ Corregido en árbol · ⏳ commit pendiente.

**Confirmación previa.** `ENCRYPTION_KEY` estaba declarada (schema + export en
`environment.js`, lista `REQUIRED_ENV` en `main.js`, `.env.example`) pero **ningún
código la usaba** (`grep` de uso funcional = 0; solo tests la seteaban por el
`required:true`).

**Corrección.** Eliminada de `auth-service/src/config/environment.js` (schema y
export), de `auth-service/src/main.js` (`REQUIRED_ENV`) y de
`auth-service/.env.example`, sustituyendo la entrada del ejemplo por una **nota**
que documenta la decisión (no dejar config muerta sin explicación) y apunta al patrón
real de cifrado en reposo (`access-service/cryptoService.js`) por si se implementa.

**Validación.** `node --check` OK en `environment.js` y `main.js`; `grep` de
`ENCRYPTION_KEY` en `src/` = 0; **suite de auth completa: 41 passed, 8 skipped**
(el arranque de `environment.js` sigue OK sin la variable). Los tests que aún setean
`ENCRYPTION_KEY` no fallan (es setup inocuo; puede limpiarse aparte).

**Comando de commit:**
```bash
git add services/auth-service/src/config/environment.js \
        services/auth-service/src/main.js \
        services/auth-service/.env.example
git commit -m "refactor(sec): A04-2 remove unused ENCRYPTION_KEY (dead config) from auth-service"
```

---

## Resumen de validación

| Hallazgo | Validación ejecutada | Resultado |
|----------|----------------------|-----------|
| A02-1 | Simulación de matching `.dockerignore` | secretos excluidos, código conservado ✅ |
| A02-2 | `grep` de secretos en los `.bak` truncados | 0 secretos ✅ |
| A03-1 | Parseo YAML de los 4 workflows | válidos, `contents: read` ✅ |
| A03-2 | Resolución de SHA vía GitHub API | 4/6 resueltos; 2 con script ⏳ |
| CLD-2 | `grep` de líneas `FROM` | 15/15 con digest ✅ |
| CLD-5 | Parseo YAML del compose | Redis sin publicar + auth ✅ |
| A04-2 | `node --check` + `jest` auth | 41 tests en verde ✅ |
