-- =============================================================================
-- Migración 012 — Crea las tablas que faltaban en fitness_service_db
-- =============================================================================
-- El esquema 02_fitness_service_db.sql no se había aplicado a la BD viva, por eso
-- catalogo_ejercicios / registros_nutricion no existían (y 011 fallaba).
-- Esta migración crea, de forma IDEMPOTENTE:
--   • catalogo_ejercicios   (imágenes wger para rutinas)
--   • registros_nutricion   (consumo diario)
--   • registros_hidratacion (agua diaria)
-- + índices, RLS y GRANTs para svc_fitness. Usa gen_random_uuid() (nativo).
-- Correr en el SQL Editor de Supabase. Reemplaza a 011 (la incluye).
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS fitness_service_db;

-- ── Enums ─────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE fitness_service_db.region_corporal_enum AS ENUM ('anterior','posterior');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE fitness_service_db.nivel_ejercicio_enum AS ENUM ('principiante','intermedio','avanzado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── catalogo_ejercicios (wger) ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fitness_service_db.catalogo_ejercicios (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_wger            INTEGER NOT NULL,
  uuid_wger          UUID,
  nombre             VARCHAR(200) NOT NULL,
  nombre_en          VARCHAR(200),
  descripcion        TEXT,
  categoria          VARCHAR(80),
  nivel              fitness_service_db.nivel_ejercicio_enum DEFAULT 'intermedio',
  equipamiento       TEXT[],
  musculo_principal  TEXT[],
  musculo_secundario TEXT[],
  region_corporal    fitness_service_db.region_corporal_enum DEFAULT 'anterior',
  imagen_url         TEXT,
  video_url          TEXT,
  thumbnail_url      TEXT,
  fuente             VARCHAR(20) NOT NULL DEFAULT 'wger',
  idioma_original    CHAR(2)     NOT NULL DEFAULT 'es',
  activo             BOOLEAN     NOT NULL DEFAULT TRUE,
  creado_en          TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  sincronizado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ejercicios_id_wger
  ON fitness_service_db.catalogo_ejercicios (id_wger);
CREATE INDEX IF NOT EXISTS idx_ejercicios_musculo_principal_gin
  ON fitness_service_db.catalogo_ejercicios USING GIN (musculo_principal);
CREATE INDEX IF NOT EXISTS idx_ejercicios_musculo_secundario_gin
  ON fitness_service_db.catalogo_ejercicios USING GIN (musculo_secundario);

ALTER TABLE fitness_service_db.catalogo_ejercicios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_catalogo_ejercicios ON fitness_service_db.catalogo_ejercicios;
CREATE POLICY read_catalogo_ejercicios ON fitness_service_db.catalogo_ejercicios
  FOR SELECT TO public USING (activo = TRUE);
GRANT SELECT ON fitness_service_db.catalogo_ejercicios TO svc_fitness;

-- ── registros_nutricion (consumo diario) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS fitness_service_db.registros_nutricion (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id          UUID NOT NULL,
  fecha               DATE NOT NULL DEFAULT CURRENT_DATE,
  comida              VARCHAR(30) NOT NULL DEFAULT 'desayuno',
  codigo_barras       VARCHAR(30),
  nombre_alimento     VARCHAR(300) NOT NULL,
  cantidad_gramos     NUMERIC(7,2) NOT NULL CHECK (cantidad_gramos > 0),
  calorias_consumidas NUMERIC(7,2),
  proteinas_g         NUMERIC(6,2),
  carbohidratos_g     NUMERIC(6,2),
  grasas_g            NUMERIC(6,2),
  creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT registros_nutricion_comida_check
    CHECK (comida IN ('desayuno','almuerzo','comida','cena','snack'))
);
CREATE INDEX IF NOT EXISTS idx_registros_nutricion_usuario_fecha
  ON fitness_service_db.registros_nutricion (usuario_id, fecha DESC);

ALTER TABLE fitness_service_db.registros_nutricion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_nutricion ON fitness_service_db.registros_nutricion;
CREATE POLICY deny_nutricion ON fitness_service_db.registros_nutricion
  FOR ALL TO public USING (false);
DROP POLICY IF EXISTS svc_fitness_rw_n ON fitness_service_db.registros_nutricion;
CREATE POLICY svc_fitness_rw_n ON fitness_service_db.registros_nutricion
  FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON fitness_service_db.registros_nutricion TO svc_fitness;

-- ── registros_hidratacion (agua diaria, upsert usuario+fecha) ─────────────────
CREATE TABLE IF NOT EXISTS fitness_service_db.registros_hidratacion (
  usuario_id     UUID NOT NULL,
  fecha          DATE NOT NULL DEFAULT CURRENT_DATE,
  total_ml       INTEGER NOT NULL DEFAULT 0 CHECK (total_ml >= 0),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (usuario_id, fecha)
);
ALTER TABLE fitness_service_db.registros_hidratacion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_hidratacion ON fitness_service_db.registros_hidratacion;
CREATE POLICY deny_hidratacion ON fitness_service_db.registros_hidratacion
  FOR ALL TO public USING (false);
DROP POLICY IF EXISTS svc_fitness_rw_h ON fitness_service_db.registros_hidratacion;
CREATE POLICY svc_fitness_rw_h ON fitness_service_db.registros_hidratacion
  FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON fitness_service_db.registros_hidratacion TO svc_fitness;
