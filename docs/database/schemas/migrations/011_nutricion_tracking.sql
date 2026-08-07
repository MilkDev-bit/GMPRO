-- =============================================================================
-- Migración 011 — Seguimiento nutricional real (consumo diario) + hidratación
-- =============================================================================
-- Objetivo:
--   1. Dar a svc_fitness acceso de LECTURA a catalogo_ejercicios (para el
--      enriquecimiento de imágenes wger de las rutinas). El 009 no lo otorgó.
--   2. Dar a svc_fitness acceso RW a registros_nutricion (diario de alimentos
--      consumidos) — antes tenía política deny-all y ningún GRANT.
--   3. Crear registros_hidratacion (agua bebida por día) + acceso RW.
--
-- Idempotente: se puede correr varias veces sin error.
-- Ejecutar en el SQL Editor de Supabase (esquema fitness_service_db).
-- =============================================================================

-- ── 1. catalogo_ejercicios: lectura para svc_fitness (imágenes de rutina) ─────
GRANT SELECT ON fitness_service_db.catalogo_ejercicios TO svc_fitness;
-- La política pública read_catalogo_ejercicios (activo = TRUE) ya permite las filas.

-- ── 2. registros_nutricion: RW para svc_fitness ───────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON fitness_service_db.registros_nutricion TO svc_fitness;

DROP POLICY IF EXISTS svc_fitness_rw_n ON fitness_service_db.registros_nutricion;
CREATE POLICY svc_fitness_rw_n ON fitness_service_db.registros_nutricion
  FOR ALL TO svc_fitness USING (true) WITH CHECK (true);

-- ── 3. registros_hidratacion: agua bebida por día (upsert por usuario+fecha) ──
CREATE TABLE IF NOT EXISTS fitness_service_db.registros_hidratacion (
  usuario_id     UUID        NOT NULL,
  fecha          DATE        NOT NULL DEFAULT CURRENT_DATE,
  total_ml       INTEGER     NOT NULL DEFAULT 0 CHECK (total_ml >= 0),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (usuario_id, fecha)
);

ALTER TABLE fitness_service_db.registros_hidratacion ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON fitness_service_db.registros_hidratacion TO svc_fitness;

DROP POLICY IF EXISTS svc_fitness_rw_h ON fitness_service_db.registros_hidratacion;
CREATE POLICY svc_fitness_rw_h ON fitness_service_db.registros_hidratacion
  FOR ALL TO svc_fitness USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS deny_hidratacion ON fitness_service_db.registros_hidratacion;
CREATE POLICY deny_hidratacion ON fitness_service_db.registros_hidratacion
  FOR ALL TO public USING (false);
