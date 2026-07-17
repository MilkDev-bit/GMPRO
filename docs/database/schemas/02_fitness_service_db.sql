-- =============================================================================
-- GymPro · Migración 002 — Schema fitness_service_db
-- =============================================================================
-- Versión      : 1.0.0
-- Motor        : PostgreSQL 15+ (Supabase)
-- Depende de   : 01_create_schemas_and_tables.sql (extensiones uuid-ossp, pg_trgm)
-- Ejecución    : SQL Editor de Supabase o psql como rol postgres/superuser
--
-- Crea el esquema del dominio de Fitness con:
--   • catalogo_ejercicios  — Biblioteca completa de ejercicios (fuente: wger API)
--   • catalogo_alimentos   — Catálogo nutricional (fuente: Open Food Facts)
--   • rutinas_usuario      — Planes de rutina generados por IA y guardados
--   • registros_nutricion  — Diario de alimentos consumidos por el usuario
--
-- Patrón: ON CONFLICT DO NOTHING en todos los UPSERTs de seeding para
-- garantizar idempotencia (re-ejecutar el seed nunca genera duplicados).
-- =============================================================================


-- =============================================================================
-- SCHEMA
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS fitness_service_db;

COMMENT ON SCHEMA fitness_service_db IS
  'Dominio de catálogos de fitness y nutrición. Gestionado por fitness-service. '
  'Poblado automáticamente por scripts de seeding desde wger y Open Food Facts.';


-- =============================================================================
-- ENUM: Región corporal del músculo (espejo del catálogo JS/Dart)
-- =============================================================================

DO $$ BEGIN
  CREATE TYPE fitness_service_db.region_corporal_enum AS ENUM (
    'anterior',   -- Vista frontal del cuerpo
    'posterior'   -- Vista posterior del cuerpo
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE fitness_service_db.nivel_ejercicio_enum AS ENUM (
    'principiante',
    'intermedio',
    'avanzado'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =============================================================================
-- TABLA: fitness_service_db.catalogo_ejercicios
-- =============================================================================
-- Catálogo centralizado de ejercicios sincronizado desde wger Workout Manager.
-- Los músculos se almacenan en el formato canónico NSCA/ACSM definido en
-- services/ai-service/src/constants/muscleGroups.js
-- (ej. 'pectoral_mayor_esternal', 'biceps_braquial', etc.)
--
-- DISEÑO CLAVE:
--   • id_wger        — PK natural de wger para idempotencia de actualizaciones
--   • musculos_*     — Array de TEXT[] para consulta GIN y joins en Flutter
--   • video_url      — URL directa al video MP4 para preview en la app
--   • embedding_vec  — VECTOR(768) reservado para búsqueda semántica futura
--                      (requiere extensión pgvector habilitada en Supabase)
-- =============================================================================

CREATE TABLE IF NOT EXISTS fitness_service_db.catalogo_ejercicios (

  -- ─── Identificación ───────────────────────────────────────────────────────
  id                    UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  id_wger               INTEGER           NOT NULL,           -- ID original en wger API
  uuid_wger             UUID,                                 -- UUID del ejercicio en wger v2

  -- ─── Contenido del ejercicio ──────────────────────────────────────────────
  nombre                VARCHAR(200)      NOT NULL,
  nombre_en             VARCHAR(200),                         -- Nombre en inglés (fallback)
  descripcion           TEXT,
  categoria             VARCHAR(80),                          -- 'Pecho', 'Espalda', 'Piernas', etc.
  nivel                 fitness_service_db.nivel_ejercicio_enum DEFAULT 'intermedio',
  equipamiento          TEXT[],                               -- ['barra', 'mancuernas', 'polea', ...]

  -- ─── Datos anatómicos (formato canónico NSCA/ACSM) ───────────────────────
  -- Claves del catálogo de muscleGroups.js
  musculo_principal     TEXT[],                               -- ['pectoral_mayor_esternal', ...]
  musculo_secundario    TEXT[],                               -- ['triceps_braquial', ...]
  region_corporal       fitness_service_db.region_corporal_enum DEFAULT 'anterior',

  -- ─── Multimedia ───────────────────────────────────────────────────────────
  imagen_url            TEXT,
  video_url             TEXT,
  thumbnail_url         TEXT,

  -- ─── Metadatos de sincronización ─────────────────────────────────────────
  fuente                VARCHAR(20)       NOT NULL DEFAULT 'wger',
  idioma_original       CHAR(2)           NOT NULL DEFAULT 'es', -- ISO 639-1
  activo                BOOLEAN           NOT NULL DEFAULT TRUE,

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  creado_en             TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  actualizado_en        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  sincronizado_en       TIMESTAMPTZ       NOT NULL DEFAULT NOW()  -- Última vez que el seed actualizó

);

-- Constraint de unicidad sobre el ID de wger (clave de idempotencia del seed)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ejercicios_id_wger
  ON fitness_service_db.catalogo_ejercicios (id_wger);

-- Índice GIN para búsqueda en arrays de músculos (consultas del AI service)
CREATE INDEX IF NOT EXISTS idx_ejercicios_musculo_principal_gin
  ON fitness_service_db.catalogo_ejercicios USING GIN (musculo_principal);

CREATE INDEX IF NOT EXISTS idx_ejercicios_musculo_secundario_gin
  ON fitness_service_db.catalogo_ejercicios USING GIN (musculo_secundario);

-- Índice GIN para búsqueda de texto libre (nombre)
CREATE INDEX IF NOT EXISTS idx_ejercicios_nombre_trgm
  ON fitness_service_db.catalogo_ejercicios USING GIN (nombre gin_trgm_ops);

-- Índice para filtrar por categoría y nivel (UI de selección de ejercicios)
CREATE INDEX IF NOT EXISTS idx_ejercicios_categoria_nivel
  ON fitness_service_db.catalogo_ejercicios (categoria, nivel)
  WHERE activo = TRUE;

-- Trigger de actualización automática
CREATE OR REPLACE FUNCTION fitness_service_db.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ejercicios_updated_at ON fitness_service_db.catalogo_ejercicios;
CREATE TRIGGER trg_ejercicios_updated_at
  BEFORE UPDATE ON fitness_service_db.catalogo_ejercicios
  FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();

COMMENT ON TABLE fitness_service_db.catalogo_ejercicios IS
  'Biblioteca de ejercicios sincronizada desde wger Workout Manager. '
  'Los IDs de músculos siguen el estándar NSCA/ACSM definido en muscleGroups.js.';

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.id_wger IS
  'ID numérico original de wger. PK natural para idempotencia del seeding.';

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.musculo_principal IS
  'Array de claves canónicas NSCA/ACSM. Indexado GIN para filtros multi-músculo.';

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.equipamiento IS
  'Array de strings descriptivos del equipo requerido. Para filtros en la app.';


-- =============================================================================
-- TABLA: fitness_service_db.catalogo_alimentos
-- =============================================================================
-- Catálogo nutricional sincronizado desde Open Food Facts (OFX).
-- Filtra productos disponibles en México y Latinoamérica.
-- Todos los valores nutricionales están por 100 gramos de producto.
--
-- DISEÑO CLAVE:
--   • codigo_barras   — EAN-13 / UPC como PK natural (string para máxima compat.)
--   • *_100g          — Valores nutricionales estandarizados por 100g (FDA/USDA)
--   • paises          — Array de códigos de país ISO 3166 para filtros regionales
--   • completitud     — Score de completitud nutricional 0-100 (calculado en seed)
--   • etiquetas       — Tags de Open Food Facts para filtros (sin gluten, vegano, etc.)
-- =============================================================================

CREATE TABLE IF NOT EXISTS fitness_service_db.catalogo_alimentos (

  -- ─── Identificación ───────────────────────────────────────────────────────
  -- Código de barras como PK string: soporta EAN-8, EAN-13, UPC-A, UPC-E
  codigo_barras         VARCHAR(30)       PRIMARY KEY,
  id_off                VARCHAR(100),                         -- ID interno Open Food Facts

  -- ─── Información del producto ─────────────────────────────────────────────
  nombre                VARCHAR(300)      NOT NULL,
  nombre_generico       VARCHAR(200),                         -- Nombre genérico normalizado (para búsqueda)
  marca                 VARCHAR(150),
  categoria             VARCHAR(150),                         -- 'Cereales', 'Lácteos', 'Carnes', etc.
  subcategoria          VARCHAR(150),
  ingredientes          TEXT,                                 -- Lista de ingredientes (texto libre)

  -- ─── Información nutricional POR 100 GRAMOS (Reglamento FDA/COFEPRIS) ────
  calorias_100g         NUMERIC(7, 2)     CHECK (calorias_100g >= 0 AND calorias_100g <= 9000),
  proteinas_100g        NUMERIC(6, 2)     CHECK (proteinas_100g >= 0),
  carbohidratos_100g    NUMERIC(6, 2)     CHECK (carbohidratos_100g >= 0),
  azucares_100g         NUMERIC(6, 2)     CHECK (azucares_100g >= 0),
  fibra_100g            NUMERIC(6, 2)     CHECK (fibra_100g >= 0),
  grasas_100g           NUMERIC(6, 2)     CHECK (grasas_100g >= 0),
  grasas_saturadas_100g NUMERIC(6, 2)     CHECK (grasas_saturadas_100g >= 0),
  grasas_trans_100g     NUMERIC(6, 2)     CHECK (grasas_trans_100g >= 0),
  sodio_mg_100g         NUMERIC(7, 2)     CHECK (sodio_mg_100g >= 0),
  calcio_mg_100g        NUMERIC(7, 2),
  hierro_mg_100g        NUMERIC(7, 2),

  -- ─── Tamaño de porción ────────────────────────────────────────────────────
  porcion_gramos        NUMERIC(6, 2),                        -- Tamaño de porción estándar en gramos
  porciones_envase      NUMERIC(5, 1),

  -- ─── Disponibilidad regional ──────────────────────────────────────────────
  paises                TEXT[],                               -- ['MX', 'CO', 'AR', 'PE', 'CL', ...]
  idioma_nombre         CHAR(5)           DEFAULT 'es',

  -- ─── Metadatos Open Food Facts ────────────────────────────────────────────
  etiquetas             TEXT[],                               -- ['sin-gluten', 'vegano', 'organico', ...]
  imagen_url            TEXT,                                 -- URL de la foto del producto
  nutriscore            CHAR(1)           CHECK (nutriscore IN ('A','B','C','D','E') OR nutriscore IS NULL),
  ecoscore              CHAR(1)           CHECK (ecoscore IN ('A','B','C','D','E') OR ecoscore IS NULL),
  -- Score de completitud nutricional calculado en el seed (0-100):
  -- Se incrementa por cada campo nutricional presente
  completitud_score     SMALLINT          NOT NULL DEFAULT 0 CHECK (completitud_score BETWEEN 0 AND 100),

  -- ─── Metadatos de sincronización ─────────────────────────────────────────
  fuente                VARCHAR(30)       NOT NULL DEFAULT 'open_food_facts',
  activo                BOOLEAN           NOT NULL DEFAULT TRUE,

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  creado_en             TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  actualizado_en        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  sincronizado_en       TIMESTAMPTZ       NOT NULL DEFAULT NOW()

);

-- Índice GIN para búsqueda de texto (nombre, marca, nombre_generico)
CREATE INDEX IF NOT EXISTS idx_alimentos_nombre_trgm
  ON fitness_service_db.catalogo_alimentos USING GIN (nombre gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_alimentos_nombre_generico_trgm
  ON fitness_service_db.catalogo_alimentos USING GIN (nombre_generico gin_trgm_ops);

-- Índice GIN para filtros por país
CREATE INDEX IF NOT EXISTS idx_alimentos_paises_gin
  ON fitness_service_db.catalogo_alimentos USING GIN (paises);

-- Índice GIN para filtros por etiquetas (vegano, sin gluten, etc.)
CREATE INDEX IF NOT EXISTS idx_alimentos_etiquetas_gin
  ON fitness_service_db.catalogo_alimentos USING GIN (etiquetas);

-- Índice para ordenar por completitud (mostrar alimentos más completos primero)
CREATE INDEX IF NOT EXISTS idx_alimentos_completitud
  ON fitness_service_db.catalogo_alimentos (completitud_score DESC)
  WHERE activo = TRUE;

-- Índice por categoría y marca para el buscador de alimentos
CREATE INDEX IF NOT EXISTS idx_alimentos_categoria_marca
  ON fitness_service_db.catalogo_alimentos (categoria, marca)
  WHERE activo = TRUE;

-- Trigger de actualización automática (reutiliza la función del schema)
DROP TRIGGER IF EXISTS trg_alimentos_updated_at ON fitness_service_db.catalogo_alimentos;
CREATE TRIGGER trg_alimentos_updated_at
  BEFORE UPDATE ON fitness_service_db.catalogo_alimentos
  FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();

COMMENT ON TABLE fitness_service_db.catalogo_alimentos IS
  'Catálogo nutricional sincronizado desde Open Food Facts. '
  'Filtra productos de México y Latinoamérica. '
  'Valores nutricionales estandarizados por 100g según COFEPRIS/FDA.';

COMMENT ON COLUMN fitness_service_db.catalogo_alimentos.codigo_barras IS
  'EAN-8, EAN-13 o UPC como PK string. Clave de idempotencia del seeding.';

COMMENT ON COLUMN fitness_service_db.catalogo_alimentos.completitud_score IS
  'Score 0-100 calculado durante el seed. Determina la calidad del registro. '
  'Campos que suman: calorías(20) + proteínas(15) + carbos(15) + grasas(15) + '
  'azúcares(10) + fibra(10) + sodio(10) + imagen(5).';


-- =============================================================================
-- TABLA: fitness_service_db.rutinas_usuario
-- =============================================================================
-- Planes de entrenamiento generados por la IA y guardados por el usuario.
-- El JSON completo del plan (con músculos, series, reps, etc.) se almacena
-- en la columna plan_json para máxima flexibilidad sin re-migrar el schema.
-- =============================================================================

CREATE TABLE IF NOT EXISTS fitness_service_db.rutinas_usuario (

  id                    UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id            UUID              NOT NULL,           -- Sin FK cruzada

  -- Plan completo retornado por el ai-service (WorkoutPlan entity)
  nombre                VARCHAR(200)      NOT NULL,
  descripcion           TEXT,
  objetivo              VARCHAR(50),                          -- 'hipertrofia', 'fuerza', 'perdida_peso', etc.
  nivel                 fitness_service_db.nivel_ejercicio_enum DEFAULT 'intermedio',
  dias_por_semana       SMALLINT          CHECK (dias_por_semana BETWEEN 1 AND 7),

  -- JSON completo del plan (inmutable después de guardado)
  plan_json             JSONB             NOT NULL,

  -- Control
  activo                BOOLEAN           NOT NULL DEFAULT TRUE,
  es_favorito           BOOLEAN           NOT NULL DEFAULT FALSE,
  veces_completada      INTEGER           NOT NULL DEFAULT 0,
  ultima_sesion_en      TIMESTAMPTZ,

  -- Auditoría
  creado_en             TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  actualizado_en        TIMESTAMPTZ       NOT NULL DEFAULT NOW()

);

CREATE INDEX IF NOT EXISTS idx_rutinas_usuario_id
  ON fitness_service_db.rutinas_usuario (usuario_id, creado_en DESC)
  WHERE activo = TRUE;

DROP TRIGGER IF EXISTS trg_rutinas_updated_at ON fitness_service_db.rutinas_usuario;
CREATE TRIGGER trg_rutinas_updated_at
  BEFORE UPDATE ON fitness_service_db.rutinas_usuario
  FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();

COMMENT ON TABLE fitness_service_db.rutinas_usuario IS
  'Planes de entrenamiento guardados. plan_json contiene el WorkoutPlan completo del ai-service.';


-- =============================================================================
-- TABLA: fitness_service_db.registros_nutricion
-- =============================================================================
-- Diario de alimentos: registro diario de lo que come el usuario.
-- Cada fila = 1 alimento consumido en 1 comida de 1 día.
-- =============================================================================

CREATE TABLE IF NOT EXISTS fitness_service_db.registros_nutricion (

  id                    UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id            UUID              NOT NULL,

  -- Fecha y comida
  fecha                 DATE              NOT NULL DEFAULT CURRENT_DATE,
  comida                VARCHAR(30)       NOT NULL DEFAULT 'desayuno'
                        CHECK (comida IN ('desayuno','almuerzo','comida','cena','snack')),

  -- Alimento consumido (referencia al catálogo)
  codigo_barras         VARCHAR(30),                          -- FK lógica al catálogo
  nombre_alimento       VARCHAR(300)      NOT NULL,           -- Desnormalizado para consultas rápidas

  -- Cantidad consumida
  cantidad_gramos       NUMERIC(7, 2)     NOT NULL CHECK (cantidad_gramos > 0),

  -- Valores nutricionales calculados (cantidad × valor_100g / 100)
  calorias_consumidas   NUMERIC(7, 2),
  proteinas_g           NUMERIC(6, 2),
  carbohidratos_g       NUMERIC(6, 2),
  grasas_g              NUMERIC(6, 2),

  -- Auditoría
  creado_en             TIMESTAMPTZ       NOT NULL DEFAULT NOW()

);

CREATE INDEX IF NOT EXISTS idx_nutricion_usuario_fecha
  ON fitness_service_db.registros_nutricion (usuario_id, fecha DESC);

COMMENT ON TABLE fitness_service_db.registros_nutricion IS
  'Diario nutricional del miembro. Cada fila representa 1 porción de alimento consumido.';


-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE fitness_service_db.catalogo_ejercicios    ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.catalogo_alimentos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.rutinas_usuario        ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.registros_nutricion    ENABLE ROW LEVEL SECURITY;

-- Catálogos son de solo lectura pública (cualquier service puede leer)
CREATE POLICY read_catalogo_ejercicios ON fitness_service_db.catalogo_ejercicios
  FOR SELECT TO public USING (activo = TRUE);

CREATE POLICY read_catalogo_alimentos ON fitness_service_db.catalogo_alimentos
  FOR SELECT TO public USING (activo = TRUE);

-- Rutinas y registros: solo service_role (bypasea RLS) puede modificar
CREATE POLICY deny_rutinas ON fitness_service_db.rutinas_usuario
  FOR ALL TO public USING (false);

CREATE POLICY deny_nutricion ON fitness_service_db.registros_nutricion
  FOR ALL TO public USING (false);


-- =============================================================================
-- VERIFICACIÓN FINAL
-- =============================================================================

DO $$
DECLARE
  tabla_count  INT;
  schema_count INT;
BEGIN
  SELECT COUNT(*) INTO tabla_count
  FROM information_schema.tables
  WHERE table_schema = 'fitness_service_db'
    AND table_type = 'BASE TABLE';

  SELECT COUNT(*) INTO schema_count
  FROM information_schema.schemata
  WHERE schema_name = 'fitness_service_db';

  RAISE NOTICE '✅ Schema fitness_service_db: % / 1 esperados', schema_count;
  RAISE NOTICE '✅ Tablas en fitness_service_db: % / 4 esperadas', tabla_count;

  IF tabla_count < 4 OR schema_count < 1 THEN
    RAISE EXCEPTION '❌ Verificación fallida. Revisar errores en la ejecución del script 002.';
  END IF;

  RAISE NOTICE '🎉 Migración 002 completada exitosamente. Lista para seeding.';
END;
$$;
