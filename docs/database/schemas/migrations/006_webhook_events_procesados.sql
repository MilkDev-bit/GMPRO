-- =============================================================================
-- MIGRACIÓN 006: webhook_events_procesados — idempotencia ATÓMICA de Stripe
-- =============================================================================
-- Versión      : 006
-- Fecha        : 2026-07-17
-- Autor        : GymPro FinTech Security
-- Descripción  : Corrige la idempotencia NO atómica del webhook de Stripe
--               (webhookController.js). El control anterior consultaba
--               isEventAlreadyProcessed() (que leía suscripciones.stripe_event_id_ultimo,
--               el "último evento" por fila) y solo marcaba el evento como procesado
--               COMO EFECTO SECUNDARIO del handler. Dos entregas concurrentes del MISMO
--               evento (Stripe garantiza at-least-once) pasaban ambas la verificación
--               y se procesaban dos veces → suscripciones/pagos duplicados.
--
--               Esta tabla es un LEDGER dedicado de eventos procesados con event_id
--               como PRIMARY KEY. El webhook hace INSERT del event_id ANTES de procesar:
--               el primero gana; una entrega concurrente/duplicada choca con la PK
--               (violación 23505) y se descarta de forma segura. Atómico e independiente
--               de qué fila de suscripción toque el evento.
--
-- EJECUCIÓN: aplicar en Supabase SQL Editor una sola vez.
-- =============================================================================

CREATE TABLE IF NOT EXISTS payment_service_db.webhook_events_procesados (
  event_id       VARCHAR(80)  PRIMARY KEY,          -- evt_xxx de Stripe (idempotencia)
  tipo           VARCHAR(80),                        -- invoice.paid, customer.subscription.deleted, ...
  procesado_en   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  resultado      VARCHAR(20)  NOT NULL DEFAULT 'ok'  -- 'ok' | 'error' (para reprocesar fallidos)
                 CHECK (resultado IN ('ok', 'error'))
);

-- Purga de eventos viejos (Stripe reintenta hasta 72h; se puede conservar 30 días).
CREATE INDEX IF NOT EXISTS idx_webhook_events_procesado_en
  ON payment_service_db.webhook_events_procesados (procesado_en);

-- RLS: solo el service_role (payment-service) accede.
ALTER TABLE payment_service_db.webhook_events_procesados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deny_all_webhook_events ON payment_service_db.webhook_events_procesados;
CREATE POLICY deny_all_webhook_events
  ON payment_service_db.webhook_events_procesados FOR ALL
  USING (false) WITH CHECK (false);

COMMENT ON TABLE payment_service_db.webhook_events_procesados IS
  'Ledger de idempotencia de webhooks de Stripe. event_id = PK: el INSERT atómico previene doble procesamiento (race at-least-once).';
