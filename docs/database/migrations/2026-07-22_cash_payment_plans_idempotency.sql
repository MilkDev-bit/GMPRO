-- =====================================================================
-- Migración: pago en efectivo — tabla de planes, idempotencia e
-- integridad financiera (auditoría Parte 2: 2.2, 2.2b, 2.3).
--
-- ⚠ VERIFICAR CONTRA LA BD DESPLEGADA ANTES DE APLICAR.
--   El archivo docs/.../01_create_schemas_and_tables.sql está DESALINEADO
--   con la BD real (usa 'plan_precio'/enum español 'activa'/'registrado_por',
--   mientras el código escribe 'monto'/'active'/'receptionist_id'). Esta
--   migración se escribió contra la forma que el CÓDIGO usa (= BD real).
--   Confirma nombres/tipos de columnas de 'suscripciones' e 'historial_pagos'
--   en la BD desplegada antes de correr la función RPC.
--
-- Idempotente: reaplicable sin efecto.
-- =====================================================================

-- ── 1. TABLA CANÓNICA DE PLANES ──────────────────────────────────────
-- El acceso (duracion_dias) es ESTRICTO y sale de aquí, no del cliente.
-- El precio es de REFERENCIA (precios dinámicos: descuentos/promos), y la
-- diferencia contra lo cobrado se audita en historial_pagos.variacion_precio.
CREATE TABLE IF NOT EXISTS payment_service_db.planes (
  plan_id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre               VARCHAR(100)  NOT NULL,
  duracion_dias        SMALLINT      NOT NULL CHECK (duracion_dias > 0 AND duracion_dias <= 3660),
  precio_base_actual   NUMERIC(10,2) NOT NULL CHECK (precio_base_actual >= 0),
  moneda               CHAR(3)       NOT NULL DEFAULT 'MXN',
  activo               BOOLEAN       NOT NULL DEFAULT TRUE,
  creado_en            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  actualizado_en       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN payment_service_db.planes.precio_base_actual IS
  'Precio de referencia vigente. El cobro real puede diferir (descuentos/promos); '
  'la diferencia se registra en historial_pagos.variacion_precio para auditoría.';

-- ⚠ SEED DE EJEMPLO — reemplaza por el catálogo REAL de GymPro antes de usar.
-- Se deja comentado para no inyectar precios ficticios en producción.
-- INSERT INTO payment_service_db.planes (nombre, duracion_dias, precio_base_actual) VALUES
--   ('Mensual Estándar',   30,  499.00),
--   ('Trimestral',         90, 1299.00),
--   ('Anual',             365, 4599.00);

-- ── 2. IDEMPOTENCIA + AUDITORÍA EN historial_pagos ───────────────────
ALTER TABLE payment_service_db.historial_pagos
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS variacion_precio NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS plan_id UUID;

-- Clave única: dos requests con la misma Idempotency-Key no pueden crear
-- dos asientos. El 23505 resultante es el guard de concurrencia.
CREATE UNIQUE INDEX IF NOT EXISTS uq_historial_pagos_idempotency
  ON payment_service_db.historial_pagos (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMENT ON COLUMN payment_service_db.historial_pagos.variacion_precio IS
  'monto_cobrado - precio_base_actual del plan al momento del pago. '
  'Negativo = descuento; positivo = recargo. Rastro contable.';

-- ── 3. FUNCIÓN RPC ATÓMICA ───────────────────────────────────────────
-- Todo ocurre en UNA transacción (plpgsql): validar plan, extender/crear
-- suscripción e insertar el asiento. Si el INSERT de historial_pagos choca
-- con la unique de idempotency_key (23505), la excepción propaga y REVIERTE
-- también la extensión de la suscripción — nunca hay doble extensión.
--
-- Retries SECUENCIALES: el SELECT inicial por idempotency_key corta antes de
-- tocar nada y devuelve ya_procesado=true.
-- Retries CONCURRENTES: ambos pasan el SELECT, uno gana el INSERT y el otro
-- recibe 23505 → su transacción entera revierte; el cliente lo trata como
-- ya_procesado y responde 200 con el asiento ganador.
CREATE OR REPLACE FUNCTION payment_service_db.registrar_pago_efectivo(
  p_usuario_id          UUID,
  p_plan_id             UUID,
  p_monto_cobrado       NUMERIC,
  p_metodo_pago         TEXT,
  p_receptionist_id     TEXT,
  p_idempotency_key     TEXT,
  p_numero_recibo       TEXT,
  p_pase_cortesia_codigo TEXT DEFAULT NULL,
  p_notas               TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = payment_service_db, public
AS $$
DECLARE
  v_plan            RECORD;
  v_existing_pago   RECORD;
  v_sub             RECORD;
  v_accion          TEXT;
  v_ahora           TIMESTAMPTZ := NOW();
  v_hoy             DATE := (v_ahora AT TIME ZONE 'America/Mexico_City')::date;
  v_valido_hasta    DATE;
  v_variacion       NUMERIC(10,2);
  v_pago            RECORD;
BEGIN
  -- 0. Idempotencia secuencial: ¿ya existe un asiento con esta clave?
  SELECT * INTO v_existing_pago
  FROM historial_pagos
  WHERE idempotency_key = p_idempotency_key;

  IF FOUND THEN
    SELECT * INTO v_sub FROM suscripciones WHERE id = v_existing_pago.suscripcion_id;
    RETURN jsonb_build_object(
      'ya_procesado', true, 'accion', 'idempotent',
      'suscripcion', to_jsonb(v_sub), 'pago', to_jsonb(v_existing_pago)
    );
  END IF;

  -- 1. Plan canónico: la duración es ESTRICTA y sale de aquí.
  SELECT plan_id, nombre, duracion_dias, precio_base_actual, moneda
  INTO v_plan
  FROM planes
  WHERE plan_id = p_plan_id AND activo = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  v_variacion := ROUND(p_monto_cobrado - v_plan.precio_base_actual, 2);

  -- 2. Extender (si hay activa) o crear suscripción — átomico con lo demás.
  SELECT * INTO v_sub
  FROM suscripciones
  WHERE usuario_id = p_usuario_id AND estado = 'active'
  ORDER BY valido_hasta DESC
  LIMIT 1;

  IF FOUND THEN
    v_valido_hasta := GREATEST(v_sub.valido_hasta, v_hoy) + v_plan.duracion_dias;
    UPDATE suscripciones SET
      plan_nombre = v_plan.nombre,
      plan_duracion_dias = v_plan.duracion_dias,
      monto = p_monto_cobrado,
      metodo_pago = p_metodo_pago,
      estado = 'active',
      valido_hasta = v_valido_hasta,
      ultimo_pago_en = v_ahora,
      receptionist_id = p_receptionist_id,
      notas_internas = p_notas,
      cancelado_en = NULL,
      acceso_facial_revocado_en = NULL,
      actualizado_en = v_ahora
    WHERE id = v_sub.id
    RETURNING * INTO v_sub;
    v_accion := 'renewed';
  ELSE
    v_valido_hasta := v_hoy + v_plan.duracion_dias;
    INSERT INTO suscripciones (
      usuario_id, plan_nombre, plan_duracion_dias, monto, moneda,
      metodo_pago, estado, valido_desde, valido_hasta, ultimo_pago_en,
      receptionist_id, notas_internas
    ) VALUES (
      p_usuario_id, v_plan.nombre, v_plan.duracion_dias, p_monto_cobrado, v_plan.moneda,
      p_metodo_pago, 'active', v_hoy, v_valido_hasta, v_ahora,
      p_receptionist_id, p_notas
    )
    RETURNING * INTO v_sub;
    v_accion := 'created';
  END IF;

  -- 3. Asiento en el ledger. Si la idempotency_key ya existe (carrera),
  --    el 23505 propaga y revierte TODO (incluida la extensión de arriba).
  INSERT INTO historial_pagos (
    usuario_id, suscripcion_id, plan_id, monto, moneda, metodo_pago,
    estado_pago, plan_nombre, plan_duracion_dias, periodo_desde, periodo_hasta,
    numero_recibo, pase_cortesia_codigo, receptionist_id, notas,
    idempotency_key, variacion_precio
  ) VALUES (
    p_usuario_id, v_sub.id, v_plan.plan_id, p_monto_cobrado, v_plan.moneda, p_metodo_pago,
    'completed', v_plan.nombre, v_plan.duracion_dias, v_sub.valido_desde, v_sub.valido_hasta,
    p_numero_recibo, p_pase_cortesia_codigo, p_receptionist_id, p_notas,
    p_idempotency_key, v_variacion
  )
  RETURNING * INTO v_pago;

  RETURN jsonb_build_object(
    'ya_procesado', false, 'accion', v_accion,
    'suscripcion', to_jsonb(v_sub), 'pago', to_jsonb(v_pago)
  );
END;
$$;

REVOKE ALL ON FUNCTION payment_service_db.registrar_pago_efectivo FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payment_service_db.registrar_pago_efectivo TO service_role;
