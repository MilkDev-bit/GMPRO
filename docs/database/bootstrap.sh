#!/usr/bin/env bash
# =============================================================================
# GymPro · Bootstrap del schema en una BD VACÍA (Supabase)
# =============================================================================
# Aplica el schema completo en orden de dependencias. Idempotente (CREATE IF NOT
# EXISTS / ADD COLUMN IF NOT EXISTS). Cada archivo corre con ON_ERROR_STOP: si algo
# falla, se detiene ahí para que reordenes/arregles y re-ejecutes.
#
# USO:
#   export DB_URL="postgresql://postgres:[PWD]@db.<ref>.supabase.co:5432/postgres"
#   bash docs/database/bootstrap.sh
#
# ⚠ PROBAR PRIMERO en una rama de Supabase (Branching) o BD scratch. Recién con
#   el bootstrap verde ahí, aplicar a la BD real (que está vacía).
# ⚠ NO ejecuta 009 (roles): eso va DESPUÉS y necesita -v passwords (ver su runbook).
# =============================================================================
set -euo pipefail
: "${DB_URL:?exporta DB_URL=postgresql://...:5432/postgres}"

BASE="docs/database"
run() { echo ">>> $1"; psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$1"; }

# 1) Fundación: extensiones (uuid-ossp, pgcrypto, pg_trgm), enums public.*,
#    schemas auth/access/payment, tablas core (usuarios, suscripciones, refresh_tokens…)
run "$BASE/schemas/01_create_schemas_and_tables.sql"

# 2) Fitness: schema + enums + set_updated_at + catalogo_alimentos (+ huérfanos, se limpian en el paso 5)
run "$BASE/schemas/02_fitness_service_db.sql"

# 3) Migraciones incrementales (orden por dependencias: 004 antes de 008 y de planes)
run "$BASE/schemas/migrations/003_add_pin_terminal_to_usuarios.sql"
run "$BASE/schemas/migrations/004_add_historial_pagos_and_courtesy.sql"
run "$BASE/schemas/migrations/005_add_qr_nonces_consumidos.sql"
run "$BASE/schemas/migrations/006_webhook_events_procesados.sql"
run "$BASE/schemas/migrations/007_ofertas.sql"
run "$BASE/schemas/migrations/008_historial_pagos_online.sql"
run "$BASE/migrations/2026-07-22_cash_payment_plans_idempotency.sql"
run "$BASE/migrations/2026-07-22_facial_revocation_idempotency.sql"
run "$BASE/migrations/2026-07-23_refresh_token_server_side_expiry.sql"
run "$BASE/migrations/2026-07-23_refresh_tokens_table_families.sql"   # refresh_tokens ya existe (01); no-op

# 4) Gaps derivados del código: passkey_credentials, zk_device_commands, 4 tablas de fitness
run "$BASE/schemas/migrations/010_schema_gaps.sql"

# 4b) Fix de enums (valores en inglés que usa el código). SIN transacción → psql -f
#     directo (ALTER TYPE ADD VALUE no admite usar el valor en la misma transacción).
echo ">>> $BASE/schemas/migrations/012_fix_enums.sql"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$BASE/schemas/migrations/012_fix_enums.sql"

# NOTA: 00_canonical_enums.sql se OMITE a propósito — es redundante con 01 (el schema
#       payment_service_db y las tablas usan los enums public.*; los enums que 00 crea
#       en payment_service_db no los usa ninguna tabla).

# 5) (OPCIONAL) limpiar huérfanos de fitness que el código NO usa (recomendado).
#    Descomenta para dejar el schema exactamente como lo espera el código.
# psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
# DROP TABLE IF EXISTS fitness_service_db.registros_nutricion CASCADE;
# DROP TABLE IF EXISTS fitness_service_db.rutinas_usuario     CASCADE;
# DROP TABLE IF EXISTS fitness_service_db.catalogo_ejercicios CASCADE;
# SQL

echo ""
echo "✅ Bootstrap del schema aplicado."
echo "   Siguiente: verifícalo con el PREFLIGHT y luego corre 009 (roles):"
echo "   psql \"\$DB_URL\" -f $BASE/schemas/migrations/009_least_privilege_roles.PREFLIGHT.sql"
