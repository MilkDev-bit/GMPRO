-- =============================================================================
-- 012 · FIX de enums — alinear valores a lo que usa el CÓDIGO (inglés)
-- Fecha: 2026-07-29 · Idempotente
-- =============================================================================
-- El DDL definió los enums en ESPAÑOL, pero todo el código de payment usa
-- valores en INGLÉS (active/past_due/cancelled/free_pass, cash/card_terminal/
-- transfer). Con service_role/PostgREST no saltaba; con pg directo el tipo se
-- valida y falla ("invalid input value for enum"). Añadimos los valores que usa
-- el código (no destructivo: los viejos quedan, sin uso).
--
-- ⚠ SIN transacción a propósito: `ALTER TYPE ... ADD VALUE` no permite USAR el
--   valor nuevo en la misma transacción, y luego hacemos SET DEFAULT con uno.
--   Ejecutar con psql en autocommit (sin BEGIN/COMMIT):
--     psql "$DB_ADMIN_URL" -v ON_ERROR_STOP=1 -f 012_fix_enums.sql
-- =============================================================================

-- estado_suscripcion_enum → valores en inglés que escribe/lee el código
ALTER TYPE public.estado_suscripcion_enum ADD VALUE IF NOT EXISTS 'active';
ALTER TYPE public.estado_suscripcion_enum ADD VALUE IF NOT EXISTS 'past_due';
ALTER TYPE public.estado_suscripcion_enum ADD VALUE IF NOT EXISTS 'cancelled';
ALTER TYPE public.estado_suscripcion_enum ADD VALUE IF NOT EXISTS 'free_pass';

-- metodo_pago_enum → 'stripe' ya existe; faltan estos
ALTER TYPE public.metodo_pago_enum ADD VALUE IF NOT EXISTS 'cash';
ALTER TYPE public.metodo_pago_enum ADD VALUE IF NOT EXISTS 'card_terminal';
ALTER TYPE public.metodo_pago_enum ADD VALUE IF NOT EXISTS 'transfer';

-- Default de estado en inglés (el DDL lo dejó en 'activa', que el código no usa)
ALTER TABLE payment_service_db.suscripciones ALTER COLUMN estado SET DEFAULT 'active';
