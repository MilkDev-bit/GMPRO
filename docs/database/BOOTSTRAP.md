# Bootstrap del schema de GymPro (BD vacía)

La BD de producción está **vacía**. Este runbook la inicializa con el schema
completo, en el orden correcto, alineado a lo que el CÓDIGO espera (ver
`SCHEMA-RECONCILIATION.md`). Script: `docs/database/bootstrap.sh`.

## Orden de aplicación
| # | Archivo | Qué aporta |
|---|---------|------------|
| 1 | `schemas/01_create_schemas_and_tables.sql` | extensiones (uuid-ossp, pgcrypto, pg_trgm), enums `public.*`, schemas auth/access/payment, tablas core (usuarios, suscripciones, refresh_tokens, …) |
| 2 | `schemas/02_fitness_service_db.sql` | schema fitness + enums + `set_updated_at` + `catalogo_alimentos` (+ huérfanos, se limpian al final) |
| 3 | `schemas/migrations/003…008` | pin_terminal, historial_pagos, qr_nonces, webhook_events, ofertas, historial_pagos online |
| 4 | `migrations/2026-07-22…07-23` | planes (cash), idempotencia revocación facial, expiry server-side, refresh_tokens families (no-op: ya existe) |
| 5 | `schemas/migrations/010_schema_gaps.sql` | **gaps del código**: passkey_credentials, zk_device_commands, ejercicios, rutinas, rutina_ejercicios, progreso_fisico |

**Se OMITE `migrations/00_canonical_enums.sql`**: es redundante con 01 (las tablas
usan los enums `public.*` de 01; los que 00 crea en `payment_service_db` no los usa
ninguna tabla). Correrlo no rompe, pero deja enums muertos.

`refresh_tokens` está definido idéntico en 01 y en la fechada `…refresh_tokens_table_families`
(ambos `IF NOT EXISTS`) → el segundo es no-op. Sin conflicto.

## Ejecución
```bash
export DB_URL="postgresql://postgres:[PWD]@db.<ref>.supabase.co:5432/postgres"
bash docs/database/bootstrap.sh
```
Cada archivo corre con `ON_ERROR_STOP=1`: si algo falla, se detiene ahí. Como todo es
idempotente, puedes arreglar y re-ejecutar sin dañar nada.

> ⚠ **Valida primero en una rama de Supabase (Branching) o BD scratch.** Solo con el
> bootstrap en verde ahí, aplícalo a la BD real (está vacía, sin datos en riesgo).
> Si algún archivo falla, mándame el error y ajustamos orden/contenido.

## Huérfanos de fitness (recomendado limpiar)
`02` crea `catalogo_ejercicios`, `rutinas_usuario`, `registros_nutricion` que el
código **no usa** (los reales están en `010`). El paso 5 (comentado) de `bootstrap.sh`
los dropea. Descoméntalo para dejar el schema exactamente como el código espera.

## Config de servicios (aparte del SQL)
Corrige `SUPABASE_DB_SCHEMA` en **Railway** (y ya en `.env` local) de:
- fitness: `fitness_schema` → `fitness_service_db`
- ai: `ai_schema` → `ai_service_db`
Los demás (auth/access/payment) ya están bien.

## Después del bootstrap
1. Verifica con el PREFLIGHT de 009 (ahora las tablas deben salir `existe=true`, `rls=true`):
   ```bash
   psql "$DB_URL" -f docs/database/schemas/migrations/009_least_privilege_roles.PREFLIGHT.sql
   ```
2. Si todo cuadra, corre **009** (roles de mínimo privilegio) con sus `-v` passwords
   (ver `009_least_privilege_roles.RUNBOOK.md`). 009 ya está alineado al schema real
   (incluye passkey_credentials y zk_device_commands; ai excluido por apátrida).

> Nota: 009 crea los roles pero la app aún conecta con `SERVICE_ROLE_KEY` (PostgREST).
> Usar los roles `svc_*` de verdad es un paso posterior (conexión `pg` directa o JWT
> con role scopeado) — ver `SCHEMA-RECONCILIATION.md`.
