# Audit 07 — Cloud-Native (OWASP Cloud-Native Application Security Top 10)

> Alcance: infraestructura gestionada **en el repo** — `docker-compose.yml`, 5×
> `services/*/Dockerfile`, `railway/*.json` y `.github/workflows/*`. Basado en
> `audit-00-mapeo.md`. Fecha: 2026-07-24. Método: revisión estática con evidencia
> `archivo:línea`. **La consola de Railway y Supabase no es auditable desde el
> repo**; esas verificaciones se marcan como limitación.

## ¿Incluye infraestructura cloud en el repo?
**Sí**, pero **no hay IaC declarativa** (Terraform/CloudFormation/Pulumi — confirmado
en `audit-00`). La "infra como código" se limita a: contenedores (Dockerfiles +
compose), configuración de despliegue PaaS (`railway/*.json`) y pipelines CI/CD. Se
procede auditando esos artefactos.

## Tabla resumen

| ID | CNAS | Hallazgo | Severidad | Evidencia |
|----|------|----------|-----------|-----------|
| CLD-1 | CNAS-3 (IAM/authZ) | **`service_role` de Supabase (God-mode, bypassa RLS) compartida por los 5 servicios**; sin roles de BD de mínimo privilegio | **Alta** | `*/src/config/database.js:16/31` |
| CLD-2 | CNAS-7 (componentes) | Imagen base pinneada por **tag** (`node:22-alpine`), no por digest | Media | `services/*/Dockerfile:4,11,16` |
| CLD-3 | CNAS-4 (CI/CD) | **Sin escaneo de imágenes ni SBOM** en el pipeline | Media | `.github/` (ausencia) |
| CLD-4 | CNAS-5 (secretos) | Secretos por **variables de entorno**, sin vault/rotación; `.env.bak.*` en disco; `.dockerignore` mal ubicado | Media | `docker-compose.yml:33`; `audit-01` A02-1/A02-2 |
| CLD-5 | CNAS-6 (red) | compose expone todos los puertos + **Redis sin contraseña**; postura de red prod no verificable | Media–Baja | `docker-compose.yml:193-195,132` |
| CLD-6 | CNAS-9 (cuotas) | **Sin límites de recursos** ni hardening de runtime (`cap_drop`/`no-new-privileges`/`read_only`) | Baja | `docker-compose.yml` (ausencia) |
| CLD-7 | CNAS-10 (logging) | Sin logging/alertas centralizadas del proveedor | Media | ver `audit-03` A09-3 |
| CLD-8 | CNAS-1 (config) | Contenedores endurecidos (non-root, alpine, multi-stage, healthcheck) | ✅ Correcto | `Dockerfile:31,33`; `railway/*.json:9-12` |

---

## CNAS-3 — Gestión de identidades y permisos (IAM) · CLD-1 (Alta)
Los **5 microservicios** instancian el cliente Supabase con la
**`SUPABASE_SERVICE_ROLE_KEY`** (`auth/access/ai/fitness/payment` →
`src/config/database.js:16/31`). El propio código lo documenta: *"Usa la
SERVICE_ROLE_KEY (bypasea RLS) … acceso total al schema"* (`auth database.js:5,24`).
- **Impacto:** es una credencial de **máximo privilegio** que **anula el RLS** y da
  acceso de lectura/escritura a **todos los schemas** (incl. cruces como
  payment→`auth_service_db`). No hay roles de BD por servicio con mínimo privilegio.
  El compromiso de **cualquier** servicio (RCE, SSRF, fuga de env) equivale a
  **compromiso total de la base de datos** de toda la plataforma. Se combina con el
  **secreto JWT/INTER simétrico compartido** (ver `audit-02` A04-1): un solo `.env`
  filtrado compromete identidad + datos de todo el sistema.
- **Remediación:** (a) crear **roles Postgres por servicio** con GRANTs mínimos
  (solo los schemas/tablas que cada uno necesita) y usar esas credenciales en lugar de
  `service_role`; reservar `service_role` para operaciones administrativas puntuales;
  (b) para los cruces de schema (biométrico), un rol específico con acceso acotado;
  (c) rotación de la `service_role` y del resto de secretos compartidos.
- **Limitación:** confirmar en la consola de Supabase que el RLS está **realmente
  habilitado** en cada tabla (el modelo deny-all depende de ello) y revisar los roles.

## CNAS-1 — Configuración de cloud/contenedores

### CLD-8 (Correcto) — Contenedores endurecidos
- **Usuario no-root:** `USER node` en los 5 Dockerfiles (`:31`).
- Base **`node:22-alpine`** mínima, build **multi-stage** (deps/builder/production),
  `npm ci --omit=dev --frozen-lockfile` (sin devDeps en imagen), `dumb-init` como
  PID 1, `HEALTHCHECK` (`Dockerfile:33`).
- **Railway:** cada servicio define `healthcheckPath: /health`, `healthcheckTimeout`
  y `restartPolicyType: ON_FAILURE` con reintentos (`railway/*.json:9-12`). Sin
  secretos embebidos en los JSON (verificado).

### IaC declarativa — No aplica
No hay Terraform/CloudFormation/Pulumi. `railway/*.json` es configuración de build/
deploy mínima (correcta), no IaC de red/IAM. No se pueden auditar reglas de red,
security groups ni políticas IAM desde el repo → **limitación** (consola Railway).

## CNAS-5 — Gestión de secretos · CLD-4 (Media)
- Los secretos se inyectan por **variables de entorno**: en local vía `env_file`
  (`docker-compose.yml:33` → `./services/*/.env`), en prod vía variables de Railway.
  **No hay** gestor de secretos dedicado (Vault, AWS/GCP Secret Manager, Doppler) ni
  mecanismo de **rotación**.
- **Higiene:** `.env` y `.env.bak.*` reales existen en el árbol de trabajo (ver
  `audit-01` A02-2) y el `.dockerignore` **no se aplica** al context de build (ver
  A02-1) → riesgo de secretos en capas del builder.
- **Positivo:** ningún secreto está versionado en git y los `railway/*.json` no los
  contienen (verificado).
- **Impacto:** las variables de entorno de Railway están cifradas por la plataforma
  (aceptable), pero sin rotación ni segregación, un secreto compartido y
  sobre-privilegiado (CLD-1) amplifica cualquier fuga.
- **Remediación:** (a) crear el `./.dockerignore` (A02-1) y borrar los `.env.bak.*`;
  (b) definir política de **rotación** de `service_role`, `JWT_SECRET`,
  `INTER_SERVICE_SECRET`, claves Stripe; (c) evaluar un secret manager si se sale de
  Railway; (d) segregar secretos por servicio en lugar de compartirlos.

## CNAS-6 — Segmentación de red y exposición · CLD-5 (Media–Baja)
- `docker-compose.yml` publica al host **todos** los puertos de servicio (3001-3005)
  y **Redis 6379** (`:193-195`), y **Redis corre sin contraseña**
  (`command: redis-server --save 60 1 --loglevel warning`, sin `--requirepass`;
  `REDIS_URL=redis://redis:6379` sin credenciales, `:132`).
- **Contexto:** es la configuración **de desarrollo** (compose, `NODE_ENV=development`);
  el comentario indica usar el **Redis Add-on de Railway** en producción. Aun así, el
  patrón commiteado (Redis sin auth, host-exposed) es un riesgo si se reutiliza.
- **Segmentación:** todos los servicios comparten `gympro-network` (bridge); no hay
  distinción **interno vs. público** — los endpoints M2M (`/internal`) se protegen por
  **secreto**, no por aislamiento de red (defensa en profundidad ausente a nivel red).
- **Remediación:** (a) en compose, **no publicar** Redis ni servicios internos al host
  (usar solo la red interna) y añadir `--requirepass`; (b) en Railway, mantener Redis
  y servicios internos en **red privada** (sin dominio público) y exponer solo las
  APIs necesarias; (c) confirmar en consola qué servicios tienen dominio público.
- **Limitación:** la exposición real en producción (dominios públicos, private
  networking, Redis add-on con auth/TLS) no es verificable desde el repo.

## CNAS-9 — Cuotas de recursos · CLD-6 (Baja)
`docker-compose.yml` **no define** `mem_limit`/`cpus`/`pids_limit` ni hardening de
runtime (`read_only`, `cap_drop: [ALL]`, `security_opt: ['no-new-privileges:true']`).
- **Impacto:** sin cuotas, una fuga de memoria o un abuso puede agotar el host; sin
  `cap_drop`/`no-new-privileges` el contenedor conserva capacidades innecesarias. Está
  parcialmente mitigado por los límites **de aplicación** (rate limiting, tamaño de
  payload) y por `USER node`, pero falta el nivel de contenedor.
- **Remediación:** añadir límites de CPU/memoria y `cap_drop: [ALL]` +
  `no-new-privileges` + `read_only: true` (con `tmpfs` para lo escribible); en Railway,
  fijar límites de recursos por servicio.

## CNAS-4 / CNAS-7 — Cadena de suministro de imágenes y paquetes

### CLD-2 (Media) — Imagen base por tag, no digest
`FROM node:22-alpine` en los 3 stages de los 5 Dockerfiles (`Dockerfile:4,11,16`). El
tag es **mutable**: un repush de `node:22-alpine` cambia la base sin control.
- **Remediación:** pinnear por **digest** (`FROM node:22-alpine@sha256:<digest>`) y
  actualizarlo de forma controlada (Dependabot soporta digests de Docker).

### CLD-3 (Media) — Sin escaneo de imágenes ni SBOM en CI
No hay Trivy/Grype/Docker Scout/Syft/Cosign en `.github/` ni en `scripts/` (grep = 0).
Combinado con la ausencia de `npm audit`/Dependabot (`audit-01` A03-3) y de SBOM
(A03-4), **las imágenes y sus dependencias no se escanean** por CVEs antes de desplegar.
- **Remediación:** añadir al pipeline (a) escaneo de imagen (Trivy/Grype) que falle en
  `HIGH/CRITICAL`; (b) generación de **SBOM** (Syft/CycloneDX) por imagen; (c)
  opcionalmente firma de imagen (Cosign) + verificación en deploy.
- **Positivo:** lockfiles + `npm ci --frozen-lockfile` dan builds de dependencias
  reproducibles (`audit-01` A03-5).

## CNAS-10 — Logging, monitoreo y alertas centralizadas · CLD-7 (Media)
Los servicios emiten logs **estructurados y redactados** a **stdout** (winston), que
Railway captura, pero **no hay** integración con logging/alertas centralizadas del
proveedor ni reglas de alerta (ver detalle en `audit-03` **A09-3**). Sin un colector +
umbrales, las señales de seguridad ya registradas no disparan detección.
- **Remediación:** exportar logs a un SIEM/observabilidad, definir alertas por umbral,
  y confirmar la **retención** en Railway (limitación: consola).

## CNAS-8 — Gestión de activos
No hay inventario de infraestructura/endpoints formal (sin OpenAPI; rutas sin versión
duplicadas — ver `audit-04` API9). A nivel cloud, sin IaC no hay inventario declarativo
de recursos. Recomendado: documentar los recursos gestionados (servicios, Redis, BD,
dominios) y su exposición.

---

## Almacenamiento (buckets/blobs)
No se gestiona **object storage** desde el backend en el repo (no hay
`supabase.storage`/`.upload()`/buckets — grep = 0; los "bucket" del código son
*date-bucketing*). Si se usa Supabase Storage para avatares (`avatarUrl`), su
configuración de **acceso público/privado y políticas** debe revisarse en la **consola
de Supabase** (limitación, fuera del repo).

## Limitaciones (requieren consola cloud)
- **Supabase:** RLS realmente habilitado por tabla, roles/grants, ACL de Storage,
  uso efectivo de `service_role`.
- **Railway:** política IAM/roles del proyecto, qué servicios son públicos vs.
  privados, Redis add-on (auth/TLS), límites de recursos, retención y alertas de logs.

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Roles de BD de **mínimo privilegio** por servicio (dejar de compartir `service_role`) + rotación | CLD-1 |
| 2 | Escaneo de imágenes + SBOM en CI; pin de base por **digest** | CLD-3 / CLD-2 |
| 3 | `./.dockerignore` + borrar `.env.bak.*` + política de rotación de secretos | CLD-4 |
| 4 | Red privada para Redis/servicios internos + Redis con auth; no publicar puertos internos | CLD-5 |
| 5 | Límites de recursos + `cap_drop`/`no-new-privileges`/`read_only` en contenedores | CLD-6 |
| 6 | Logging/alertas centralizadas del proveedor | CLD-7 |

> Balance: la **construcción** de contenedores es sólida (non-root, alpine,
> multi-stage, healthchecks) y no hay secretos en git. Los riesgos cloud reales son de
> **IAM/mínimo privilegio** (una `service_role` God-mode compartida, CLD-1, es el
> hallazgo de mayor impacto), **cadena de suministro de imágenes** (sin escaneo/SBOM,
> base por tag) y **gestión de secretos/red** sin segregación. Varios puntos comparten
> raíz con auditorías previas (secreto compartido A04-1, alertas A09-3, SBOM/SCA A03).
