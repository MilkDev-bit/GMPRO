-- =====================================================================
-- Migración: idempotencia de la revocación de acceso facial por cron.
--
-- CONTEXTO (auditoría 2.3): el acceso facial ZKTeco solo se revocaba en
-- customer.subscription.deleted (fin del dunning de Stripe, 7-14 días).
-- Se añade una revocación diaria por vencimiento de valido_hasta
-- (grace period = 0). Esta columna evita reenviar el DELETE al mismo
-- usuario en cada corrida del cron: se sella al revocar y se limpia al
-- reactivar la membresía.
--
-- Idempotente: se puede reaplicar sin efecto.
-- =====================================================================

ALTER TABLE payment_service_db.suscripciones
  ADD COLUMN IF NOT EXISTS acceso_facial_revocado_en TIMESTAMPTZ;

COMMENT ON COLUMN payment_service_db.suscripciones.acceso_facial_revocado_en IS
  'Marca de tiempo en que el cron de retención empujó el DELETE facial a ZKTeco '
  'por vencimiento de valido_hasta. NULL = acceso facial vigente o ya reactivado. '
  'Se limpia (vuelve a NULL) cuando la membresía se reactiva tras un pago.';

-- Índice parcial: la consulta del cron filtra exactamente por revocado IS NULL.
-- El índice parcial mantiene barato el escaneo diario aunque la tabla crezca.
CREATE INDEX IF NOT EXISTS idx_suscripciones_pendiente_revocacion_facial
  ON payment_service_db.suscripciones (valido_hasta)
  WHERE acceso_facial_revocado_en IS NULL;
