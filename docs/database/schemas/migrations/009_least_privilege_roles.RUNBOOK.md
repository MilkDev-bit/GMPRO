# Runbook — Ejecución en STAGING de la migración 009 (roles de mínimo privilegio · CLD-1)

Objetivo: crear en **staging** un rol Postgres `svc_<servicio>` por microservicio,
con permisos mínimos, y **validar el modelo** con pruebas `SET ROLE`, sin tocar
producción. La 009 es idempotente y reversible.

## Archivos
| Archivo | Qué hace | Cuándo |
|---|---|---|
| `009_least_privilege_roles.PREFLIGHT.sql` | Solo lectura: confirma schemas/tablas/funciones/RLS reales | **1º** |
| `009_least_privilege_roles.sql` | Crea roles + GRANTs + policies (idempotente, transaccional) | 2º |
| `009_least_privilege_roles.VERIFY.sql` | Checks de catálogo + pruebas `SET ROLE` (positivas y de aislamiento) | 3º |
| `009_least_privilege_roles.ROLLBACK.sql` | Borra policies + roles (revertir) | si algo falla |

> ⚠ **La 009 NO cambia cómo conecta la app.** Hoy los 5 servicios usan PostgREST
> con `SERVICE_ROLE_KEY` (que bypassa RLS). Los roles `svc_*` **solo se usarán**
> cuando cada servicio migre a conexión `pg` directa con su credencial (o a un JWT
> con `role` scopeado para PostgREST). Esta migración **crea y valida** el modelo a
> nivel de base de datos; **cablear la app es un paso posterior** (ver §5).

---

## 0. Requisitos
- Acceso a la BD de **staging** (no producción). Cadena de conexión directa
  (`postgresql://postgres:...@<host>:5432/postgres`), no el pooler PgBouncer si vas
  a usar `SET ROLE` / transacciones.
- Cliente **`psql`** (la 009 usa variables `-v`, que el SQL Editor de Supabase **no**
  interpola). El PREFLIGHT y el VERIFY sí se pueden correr en el SQL Editor.

### 0-bis. PRERREQUISITO: staging debe reflejar el schema de producción
009 crea roles sobre las tablas de la app; si staging está **vacío** (solo los
schemas por defecto de Supabase: auth/storage/realtime/…), no hay nada sobre lo que
operar. Clona **solo el schema** (sin datos) de producción a staging:
```bash
pg_dump "$PROD_DB_URL" --schema-only --no-owner --no-privileges \
  --schema=auth_service_db --schema=access_service_db \
  --schema=payment_service_db --schema=fitness_service_db --schema=ai_service_db \
  -f /tmp/gympro_schema.sql
# si alguna tabla usa pgvector:
psql "$STAGING_DB_URL" -c "create extension if not exists vector;"
psql "$STAGING_DB_URL" -f /tmp/gympro_schema.sql
```
`--schema-only` es solo lectura sobre prod. Conserva tablas, enums, funciones y las
policies RLS deny-all; descarta ownership/grants. **La versión de `pg_dump` debe ser
≥ la del servidor** (Supabase suele ser PG15/17); si tu `pg_dump` local es más viejo,
usa uno acorde (p. ej. `docker run --rm postgres:17 pg_dump ...`).
Alternativa nativa: **Supabase Branching** (crea una rama que replica el schema de prod).
Tras el clon, corre el PREFLIGHT: ahora las tablas deben salir `existe=true`.

## 1. Pre-flight (confirmar el schema real)
Corre `PREFLIGHT.sql` y valida los criterios del final del archivo. Presta atención a:
- **`ejercicios` vs `catalogo_ejercicios`** (punto 3): si el nombre real difiere,
  ajústalo en `009_least_privilege_roles.sql` (la tabla y la policy `svc_fitness_ro_e`).
- **RLS activo** (`rowsecurity=true`) en todas las tablas objetivo (punto 2).
- **Tablas pgvector de ai** (punto 4): añádelas a la sección 5 de la 009 si aplican.
- **Funciones** existen con su firma (punto 5).

No sigas hasta que el pre-flight cuadre.

## 2. Generar contraseñas (una por servicio, fuera del repo)
```bash
export AUTH_DB_PASSWORD=$(openssl rand -base64 24)
export ACCESS_DB_PASSWORD=$(openssl rand -base64 24)
export PAYMENT_DB_PASSWORD=$(openssl rand -base64 24)
export FITNESS_DB_PASSWORD=$(openssl rand -base64 24)
export AI_DB_PASSWORD=$(openssl rand -base64 24)
```
Guárdalas en tu gestor de secretos. **Nunca** las commitees ni las pegues en el SQL.

## 3. Ejecutar la migración
```bash
psql "$STAGING_DB_URL" \
  -v AUTH_DB_PASSWORD="$AUTH_DB_PASSWORD" \
  -v ACCESS_DB_PASSWORD="$ACCESS_DB_PASSWORD" \
  -v PAYMENT_DB_PASSWORD="$PAYMENT_DB_PASSWORD" \
  -v FITNESS_DB_PASSWORD="$FITNESS_DB_PASSWORD" \
  -v AI_DB_PASSWORD="$AI_DB_PASSWORD" \
  -f docs/database/schemas/migrations/009_least_privilege_roles.sql
```
Todo va dentro de una transacción con `ON_ERROR_STOP`: si algo falla, **no** deja
estado a medias. Los roles se crean solo si no existían; las policies se re-crean
(`DROP ... IF EXISTS`), así que re-ejecutar es seguro.

## 4. Verificar
Corre `VERIFY.sql` (SQL Editor o psql) y revisa:
- Puntos 1–4: los valores coinciden con las líneas "Esperado".
- Puntos 5–6: en los mensajes/NOTICE solo deben aparecer líneas **`OK `**. Cualquier
  `✗ FALLO DE AISLAMIENTO` significa que un rol ve un dominio que no debería → revisa
  sus `GRANT`/`USAGE` en la 009.

## 5. Después de validar (fuera de staging-DDL)
El modelo quedó probado a nivel de BD. Para que **rinda** en la práctica, falta el
cableado de la app (paso mayor, por servicio):
1. Cambiar cada servicio de `@supabase/supabase-js` (service_role) a **conexión `pg`
   directa** usando `svc_<servicio>` + su password (nueva var de entorno, p. ej.
   `SERVICE_DB_URL`), **o** emitir un JWT con `role: svc_<servicio>` para PostgREST.
2. Probar el servicio end-to-end contra staging con el rol nuevo.
3. Solo cuando **todos** usen su rol: revocar los privilegios de rutina de
   `service_role` y **rotar** su clave (dejarlo solo para administración).

## Rollback
Si algo sale mal en staging:
```bash
psql "$STAGING_DB_URL" -f docs/database/schemas/migrations/009_least_privilege_roles.ROLLBACK.sql
```
Borra las policies `svc_*`, revoca privilegios (`DROP OWNED BY`) y elimina los 5 roles.
La verificación final del script debe devolver **0 filas**.

## Pendiente de producción
- Repetir el ciclo pre-flight → migración → verify en **producción** solo tras validar
  staging y tras completar §5 en al menos un servicio piloto.
- Rotación de passwords `svc_*`: re-ejecuta la 009 con nuevas variables `-v`
  (cada corrida hace `ALTER ROLE ... PASSWORD`, así que rota la clave del rol existente).
