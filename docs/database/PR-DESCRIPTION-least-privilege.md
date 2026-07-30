# feat(security/CLD-1): roles de mínimo privilegio en BD + reconciliación canónica de schema

## Resumen
Cierra **CLD-1**: la app deja de operar en *god-mode* (`service_role` que bypassa RLS) y
pasa a un **rol Postgres acotado por servicio**. Al inicializar la BD (que estaba **vacía**)
y migrar a mínimo privilegio, se descubrió que el **DDL del repo diverge profundamente del
código** — producción nunca corrió con el `01`/`02`. Este PR también **reconcilia el schema**
al código y deja una **fuente de verdad canónica**.

## Qué cambia

### 1. Roles de mínimo privilegio (CLD-1)
| Servicio | Enfoque | Rol |
|---|---|---|
| **payment**, **auth** | `pg` directo (reescritura de la capa de datos a SQL parametrizado) | `svc_payment`, `svc_auth` |
| **fitness**, **access** | JWT scopeado (PostgREST `SET ROLE`, coexistencia con fallback a service_role) | `svc_fitness`, `svc_access` |
| **ai** | sin BD (apátrida) | — |

- `009_least_privilege_roles.sql` — crea los roles `svc_*` (`NOBYPASSRLS`) + GRANTs mínimos + policies (idempotente, por `psql -v`). + PREFLIGHT/VERIFY/ROLLBACK/RUNBOOK.
- `011_wiring_least_privilege.sql` — `GRANT svc_fitness/svc_access TO authenticator`, cruce access→payment, `search_path` por rol.

### 2. Reconciliación de schema (código = fuente de verdad)
El `01`/`02` estaba desalineado con el código. Correcciones:
- `010_schema_gaps.sql` — tablas y columnas que el código usa pero el DDL no definía
  (passkey_credentials, zk_device_commands, 4 tablas de fitness, columnas de suscripciones/usuarios).
- `012_fix_enums.sql` — valores de enum en inglés que usa el código (estado_suscripcion, metodo_pago).
- `013_canonical_access.sql` — **recrea las tablas de access** (`historial_accesos`, `tickets_visitas`,
  `qr_nonces_consumidos`) alineadas al código (eran un diseño totalmente distinto → access estaba roto).
- `CANONICAL_SCHEMA.sql` — **schema autoritativo** (pg_dump de la BD ya reconciliada). `01`/`02`
  quedan marcados como parcialmente obsoletos apuntando a este archivo.
- Fix cruzado: el worker de payment leía `historial_accesos.creado_en`; la columna real es `fecha_hora`.

### 3. Docs
`SCHEMA-RECONCILIATION.md`, `SCHEMA-DIVERGENCE-REPORT.md`, `WIRING-least-privilege.md`,
`BOOTSTRAP.md`, `bootstrap.sh`.

## Hallazgos clave
- La BD de producción estaba **vacía**; el schema se construyó desde el código.
- El DDL del repo (`01`/`02`, enums) es un **diseño abandonado**: `historial_accesos`/`tickets_visitas`
  eran completamente distintos; enums en español vs código en inglés; columnas faltantes en suscripciones.
- Estos desajustes eran **invisibles** con service_role/PostgREST; solo afloraron al validar tipos con `pg`.

## ⚠ Riesgos y orden de despliegue (LEER ANTES DE MERGE)
**payment y auth son CUTOVER DURO**: sus modelos `pg` exigen `PAYMENT_DATABASE_URL`/`AUTH_DATABASE_URL`;
sin ellas, el servicio no arranca. **No mergees ni despliegues el código sin la config primero.**

Orden correcto (BD → env → deploy):
1. **BD** — aplicar migraciones (esta BD ya las tiene; para un entorno nuevo):
   `bootstrap.sh` (01/02/003-008/010/012) → `009` (roles, con `-v` passwords) → `011` (wiring) → `013`.
   Alternativa fresca: `009` (roles) → `CANONICAL_SCHEMA.sql`.
2. **Variables Railway**:
   - `PAYMENT_DATABASE_URL`, `AUTH_DATABASE_URL` = cadena del **Session Pooler** (`svc_*.<ref>@…pooler.supabase.com:5432`).
   - `SUPABASE_JWT_SECRET` + `SUPABASE_ANON_KEY` (fitness, access).
   - Corregir `SUPABASE_DB_SCHEMA` de fitness (`fitness_service_db`) y ai (`ai_service_db`).
3. **Deps**: `pg` ya está en `package.json` de payment/auth (build normal lo instala).
4. **Deploy** de los 5 servicios.
5. **Rotar secretos** expuestos durante la implementación: `postgres`, `svc_payment`, `svc_auth`.
6. **Cierre CLD-1** (cuando los 5 usen su rol en prod): revocar privilegios de rutina de `service_role` y rotar su clave.

## Validación realizada
- **payment**: unit 30/30 ✓, integración de idempotencia de webhook 3/3 ✓, worker de retención (3 fases) ✓ como `svc_payment`.
- **auth**: `node --check` de todos los archivos ✓; svc_auth lee sus 4 tablas por pooler sin `permission denied` ✓.
- **SQL**: balance/idempotencia validados; `013` aplicado y verificado (columnas de `historial_accesos` = código).

## Rollback
- Roles: `009_least_privilege_roles.ROLLBACK.sql` (drop policies + roles).
- Código: revertir el merge; con las variables `*_DATABASE_URL` fuera, payment/auth vuelven a fallar
  (cutover duro) — para revertir de verdad, revertir el código de sus modelos.
- JWT (fitness/access): quitar `SUPABASE_JWT_SECRET`/`ANON_KEY` → vuelven a `service_role` (coexistencia).

## Notas post-merge
- Verificar en la app móvil que el perfil envía los valores en español de `sexo_biologico`/`nivel_actividad`
  (el backend no los constata; el enum es la única restricción).
- El `node_modules` local de un `npm start` puro topa con la resolución de `packages_shared` (jsonwebtoken/winston);
  no afecta a Railway ni a la migración.
