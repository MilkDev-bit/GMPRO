-- =============================================================================
-- MIGRACIÓN 004: historial_pagos (ledger de pagos presenciales) + pase cortesía
-- =============================================================================
-- Versión      : 004
-- Fecha        : 2026-07-17
-- Autor        : GymPro Engineering
-- Descripción  : Da soporte a la Tarea 3.4 (pago presencial en mostrador).
--
--   1. Crea payment_service_db.historial_pagos: ledger inmutable de cada
--      transacción presencial (efectivo o terminal física) registrada por el
--      staff de recepción. Es el "libro de caja" auditado que respalda cada
--      renovación manual de suscripción.
--
--   2. Guarda el vínculo con el pase de cortesía (tickets_visitas del
--      access-service) que se imprime en el ticket térmico y sirve para
--      ingresar el mismo día sin depender de la sincronización del móvil.
--
-- NOTA DE CONVENCIÓN: Se usan valores en INGLÉS ('cash', 'completed', 'active')
--   por coherencia con los modelos JS en ejecución (subscriptionModel.js) y con
--   access-service/paymentClientService.js, que ya consultan estado = 'active'.
--   Esta tabla es nueva y autoconsistente: no depende de los ENUM heredados.
--
-- EJECUCIÓN: Aplicar en Supabase SQL Editor una sola vez, en orden.
-- =============================================================================

-- ── 1. Tabla ledger de pagos presenciales ───────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_service_db.historial_pagos (

  id                     UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Vínculos (mismo esquema; sin FK cruzada a auth_service_db)
  suscripcion_id         UUID,                       -- Suscripción creada/renovada por este pago
  usuario_id             UUID          NOT NULL,      -- Socio beneficiario (desnormalizado)

  -- Transacción
  monto                  NUMERIC(10, 2) NOT NULL CHECK (monto > 0),
  moneda                 CHAR(3)        NOT NULL DEFAULT 'MXN',
  metodo_pago            VARCHAR(20)    NOT NULL DEFAULT 'cash'
                         CHECK (metodo_pago IN ('cash', 'card_terminal', 'transfer')),
  estado_pago            VARCHAR(20)    NOT NULL DEFAULT 'completed'
                         CHECK (estado_pago IN ('completed', 'refunded', 'voided')),

  -- Contexto del plan cubierto
  plan_nombre            VARCHAR(100),
  plan_duracion_dias     SMALLINT       CHECK (plan_duracion_dias IS NULL OR plan_duracion_dias > 0),
  periodo_desde          TIMESTAMPTZ,
  periodo_hasta          TIMESTAMPTZ,

  -- Comprobante físico
  numero_recibo          VARCHAR(50),                -- Folio legible impreso en el ticket
  pase_cortesia_codigo   VARCHAR(40),                -- codigo_ticket del pase de cortesía del día

  -- Auditoría (trazabilidad OWASP A09)
  receptionist_id        VARCHAR(80)    NOT NULL,     -- ID del recepcionista (de la API Key)
  notas                  TEXT,
  creado_en              TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ── 2. Índices de consulta ──────────────────────────────────────────────────
-- Historial del socio (pantalla de facturación en la app)
CREATE INDEX IF NOT EXISTS idx_hp_usuario_fecha
  ON payment_service_db.historial_pagos (usuario_id, creado_en DESC);

-- Corte de caja por recepcionista / fecha
CREATE INDEX IF NOT EXISTS idx_hp_recepcionista_fecha
  ON payment_service_db.historial_pagos (receptionist_id, creado_en DESC);

-- Folio de recibo único cuando exista
CREATE UNIQUE INDEX IF NOT EXISTS uq_hp_numero_recibo
  ON payment_service_db.historial_pagos (numero_recibo)
  WHERE numero_recibo IS NOT NULL;

-- ── 3. Inmutabilidad del ledger (no UPDATE/DELETE) ──────────────────────────
-- Un ledger de caja no se edita: las correcciones se hacen con un asiento
-- inverso (estado_pago = 'refunded' / 'voided' en un nuevo registro).
CREATE OR REPLACE FUNCTION payment_service_db.deny_ledger_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'historial_pagos es inmutable: usa un asiento inverso. [AUDIT-004]';
END;
$$;

DROP TRIGGER IF EXISTS trg_hp_no_mutation ON payment_service_db.historial_pagos;
CREATE TRIGGER trg_hp_no_mutation
  BEFORE UPDATE OR DELETE ON payment_service_db.historial_pagos
  FOR EACH ROW EXECUTE FUNCTION payment_service_db.deny_ledger_mutation();

-- ── 4. Row Level Security ───────────────────────────────────────────────────
-- Los microservicios usan SERVICE_ROLE_KEY (bypass de RLS). Bloqueamos todo
-- acceso público/authenticated por defecto.
ALTER TABLE payment_service_db.historial_pagos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deny_all_historial_pagos ON payment_service_db.historial_pagos;
CREATE POLICY deny_all_historial_pagos
  ON payment_service_db.historial_pagos FOR ALL
  USING (false) WITH CHECK (false);

COMMENT ON TABLE payment_service_db.historial_pagos IS
  'Ledger inmutable de pagos presenciales (efectivo/terminal) registrados en recepción. Tarea 3.4.';
COMMENT ON COLUMN payment_service_db.historial_pagos.pase_cortesia_codigo IS
  'codigo_ticket del pase de cortesía (access_service_db.tickets_visitas) impreso para ingreso del mismo día.';
