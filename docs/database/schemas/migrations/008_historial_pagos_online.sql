-- =============================================================================
-- MIGRACIÓN 008: historial_pagos admite pagos ONLINE (Stripe)
-- Fecha: 2026-07-24 · Servicio: payment-service
-- =============================================================================
-- El ledger historial_pagos solo asentaba pagos presenciales (cash/terminal/
-- transfer) y exigía receptionist_id. Para que los ingresos de Stripe entren en
-- el dashboard financiero (GET /admin/finance/series), el webhook invoice.paid
-- ahora asienta también aquí. Esta migración habilita ese caso:
--   1. metodo_pago admite 'stripe'.
--   2. receptionist_id deja de ser obligatorio (los online no tienen recepción).
--   3. stripe_event_id para trazabilidad + índice único → idempotencia del asiento.
--   4. CHECK de auditoría: presencial conserva recepcionista; online trae event_id.
-- Idempotente y seguro de re-ejecutar.
-- =============================================================================

-- 1. Ampliar el CHECK de metodo_pago (la restricción inline se llama
--    historial_pagos_metodo_pago_check por convención de Postgres).
ALTER TABLE payment_service_db.historial_pagos
  DROP CONSTRAINT IF EXISTS historial_pagos_metodo_pago_check;
ALTER TABLE payment_service_db.historial_pagos
  DROP CONSTRAINT IF EXISTS chk_hp_metodo_pago;
ALTER TABLE payment_service_db.historial_pagos
  ADD CONSTRAINT chk_hp_metodo_pago
  CHECK (metodo_pago IN ('cash', 'card_terminal', 'transfer', 'stripe'));

-- 2. receptionist_id opcional (pagos online no tienen recepcionista).
ALTER TABLE payment_service_db.historial_pagos
  ALTER COLUMN receptionist_id DROP NOT NULL;

-- 3. Trazabilidad del evento Stripe + idempotencia del asiento online.
ALTER TABLE payment_service_db.historial_pagos
  ADD COLUMN IF NOT EXISTS stripe_event_id VARCHAR(80);
CREATE UNIQUE INDEX IF NOT EXISTS uq_hp_stripe_event
  ON payment_service_db.historial_pagos (stripe_event_id)
  WHERE stripe_event_id IS NOT NULL;

-- 4. Auditoría: presencial ⇒ recepcionista; online ⇒ stripe_event_id.
ALTER TABLE payment_service_db.historial_pagos
  DROP CONSTRAINT IF EXISTS chk_hp_auditoria;
ALTER TABLE payment_service_db.historial_pagos
  ADD CONSTRAINT chk_hp_auditoria
  CHECK (
    (metodo_pago = 'stripe' AND stripe_event_id IS NOT NULL)
    OR (metodo_pago <> 'stripe' AND receptionist_id IS NOT NULL)
  );

COMMENT ON COLUMN payment_service_db.historial_pagos.stripe_event_id IS
  'ID del evento Stripe (evt_…) que generó el asiento online. Único → idempotencia.';
