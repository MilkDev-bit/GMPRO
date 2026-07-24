-- =============================================================================
-- MIGRACIÓN 007: ofertas — cupones/ofertas especiales gestionadas desde el panel
-- Fecha: 2026-07-24 · Servicio: payment-service
-- =============================================================================
-- Descuentos aplicables a la contratación/renovación de suscripciones. El panel
-- (staff/admin) los crea, activa/desactiva y consulta. Como el resto de tablas
-- sensibles: RLS deny-all → solo service_role (los microservicios) accede.
-- =============================================================================

CREATE TABLE IF NOT EXISTS payment_service_db.ofertas (
  id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre        VARCHAR(120) NOT NULL,
  codigo        VARCHAR(40)  NOT NULL,
  tipo          VARCHAR(20)  NOT NULL
                CHECK (tipo IN ('porcentaje', 'monto_fijo', 'meses_gratis')),
  -- porcentaje: 0..100 | monto_fijo: importe | meses_gratis: nº de meses
  valor         NUMERIC(10,2) NOT NULL CHECK (valor >= 0),
  activa        BOOLEAN       NOT NULL DEFAULT TRUE,
  valido_desde  TIMESTAMPTZ   NOT NULL,
  valido_hasta  TIMESTAMPTZ   NOT NULL,
  usos          INTEGER       NOT NULL DEFAULT 0 CHECK (usos >= 0),
  max_usos      INTEGER       CHECK (max_usos IS NULL OR max_usos > 0),
  creado_en     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_vigencia CHECK (valido_hasta > valido_desde)
);

-- El código es único de forma case-insensitive (los cupones no distinguen mayúsc.)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ofertas_codigo
  ON payment_service_db.ofertas (LOWER(codigo));

CREATE INDEX IF NOT EXISTS idx_ofertas_activas
  ON payment_service_db.ofertas (activa) WHERE activa = TRUE;

-- ── RLS: deny-all (solo service_role accede) ────────────────────────────────
ALTER TABLE payment_service_db.ofertas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_all_ofertas ON payment_service_db.ofertas;
CREATE POLICY deny_all_ofertas
  ON payment_service_db.ofertas FOR ALL
  TO public USING (false);

COMMENT ON TABLE payment_service_db.ofertas IS
  'Ofertas/cupones de descuento gestionados desde el panel admin. RLS deny-all.';

-- ── Incremento ATÓMICO de usos (canje) ───────────────────────────────────────
-- El webhook de Stripe lo invoca vía RPC. `UPDATE ... SET usos = usos + 1` es
-- atómico en Postgres → dos canjes concurrentes del mismo código no se pisan.
-- SECURITY DEFINER + revoke a public: solo ejecutable por service_role.
CREATE OR REPLACE FUNCTION payment_service_db.increment_offer_usage(p_codigo TEXT)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = payment_service_db
AS $$
DECLARE
  nuevos INTEGER;
BEGIN
  UPDATE payment_service_db.ofertas
     SET usos = usos + 1, actualizado_en = NOW()
   WHERE LOWER(codigo) = LOWER(p_codigo)
  RETURNING usos INTO nuevos;
  RETURN nuevos; -- NULL si el código no existe
END;
$$;

REVOKE ALL ON FUNCTION payment_service_db.increment_offer_usage(TEXT) FROM PUBLIC;
