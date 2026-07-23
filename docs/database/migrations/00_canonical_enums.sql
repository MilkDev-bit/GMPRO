-- =====================================================================
-- ENUMs canónicos — EN INGLÉS, alineados con lo que el código escribe/lee.
--
-- CONTEXTO: no existe BD desplegada aún. Por tanto NO hay que migrar ni
-- renombrar nada (ningún ALTER TYPE ... RENAME VALUE): se DEFINE el enum
-- correcto de una sola vez, en el idioma del código. El archivo
-- 01_create_schemas_and_tables.sql (enums en español: 'activa','vencida'…)
-- quedó como documentación equivocada y NO debe aplicarse.
--
-- Aplicar ANTES de crear las tablas que usan estos tipos.
-- Idempotente.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS payment_service_db;

-- ── Estado de suscripción ────────────────────────────────────────────
-- Valores que el código realmente maneja:
--   escribe: 'active' (activateAfterPayment/registerCash), 'past_due'
--            (markPaymentFailed), 'cancelled' (cancelSubscription)
--   lee/filtra: 'active', 'past_due' (payment) y 'active','free_pass'
--            (access-service, membresía de cortesía/comp)
-- 'suspended' se incluye para pausas administrativas (viaje/lesión) aunque
-- hoy ningún código lo escriba: un enum de más es inocuo; uno de menos
-- provoca 22P02 al primer INSERT con un valor no contemplado.
DO $$ BEGIN
  CREATE TYPE payment_service_db.estado_suscripcion_enum AS ENUM (
    'active', 'past_due', 'cancelled', 'free_pass', 'suspended'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Método de pago ───────────────────────────────────────────────────
-- rutas cash-payment: 'cash' | 'card_terminal' | 'transfer'
-- webhook Stripe:      'stripe'
DO $$ BEGIN
  CREATE TYPE payment_service_db.metodo_pago_enum AS ENUM (
    'cash', 'card_terminal', 'transfer', 'stripe'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Estado de pago (historial_pagos.estado_pago) ─────────────────────
-- El código solo escribe 'completed'; se añaden estados de ciclo de vida
-- previsibles para no bloquear futuras rutas de reembolso/pendiente.
DO $$ BEGIN
  CREATE TYPE payment_service_db.estado_pago_enum AS ENUM (
    'pending', 'completed', 'failed', 'refunded'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =====================================================================
-- RECONCILIACIÓN CON LA RPC registrar_pago_efectivo (ronda anterior):
--   · WHERE estado = 'active'                → valor presente en el enum ✓
--   · UPDATE/INSERT estado = 'active'        → ✓
--   · INSERT estado_pago = 'completed'       → presente en estado_pago_enum ✓
--   · metodo_pago = p_metodo_pago            → 'cash'/'card_terminal'/
--                                              'transfer' (validado en ruta) ✓
-- La RPC es 100% compatible con estos tipos: todos los literales que usa
-- existen en los enums de arriba. NOTA: si en tu BD final decides que
-- 'estado'/'metodo_pago' sean columnas TEXT en vez de ENUM, la RPC también
-- funciona sin cambios (las comparaciones son por string).
-- =====================================================================
