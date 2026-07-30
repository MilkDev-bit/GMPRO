-- =============================================================================
-- 010 · SCHEMA GAPS — tablas que el CÓDIGO usa pero el DDL nunca definió
-- Fecha: 2026-07-29 · Idempotente · Ver docs/database/SCHEMA-RECONCILIATION.md
-- =============================================================================
-- ⚠ ORDEN EN EL BOOTSTRAP: este archivo va DESPUÉS de 01/02 y de las migraciones
--   003–008, y ANTES de 009 (roles), porque 009 concede permisos sobre estas tablas.
--   El número (010) es solo identificador; el orden lo manda el runbook de bootstrap.
--
-- Cada tabla se derivó por reverse-engineering de los modelos del servicio
-- correspondiente (columnas, tipos, FKs, defaults). Sigue las convenciones del
-- schema base: PK UUID, actualizado_en + trigger set_updated_at, RLS deny-all.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- auth_service_db.passkey_credentials  (WebAuthn / Passkeys)
--   Fuente: services/auth-service/src/models/passkeyModel.js
--   insert: user_id, credential_id, public_key, counter, transports, device_name
--   update: counter, ultimo_uso ·  lookup único por credential_id ·  FK → usuarios
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_service_db.passkey_credentials (
  id             UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID         NOT NULL REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE,
  credential_id  TEXT         NOT NULL UNIQUE,                       -- WebAuthn credential ID (base64url)
  public_key     TEXT         NOT NULL,                             -- llave pública en base64 (ver modelo)
  counter        BIGINT       NOT NULL DEFAULT 0,                   -- contador de firma WebAuthn
  transports     TEXT[]       NOT NULL DEFAULT '{}',                -- ['internal','hybrid',...]
  device_name    VARCHAR(100) NOT NULL DEFAULT 'Dispositivo Móvil',
  ultimo_uso     TIMESTAMPTZ,                                       -- se setea en cada verificación
  creado_en      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_passkey_user_id
  ON auth_service_db.passkey_credentials(user_id);   -- findCredentialsByUserId

DROP TRIGGER IF EXISTS trg_passkey_credentials_updated_at ON auth_service_db.passkey_credentials;
CREATE TRIGGER trg_passkey_credentials_updated_at
  BEFORE UPDATE ON auth_service_db.passkey_credentials
  FOR EACH ROW EXECUTE FUNCTION auth_service_db.set_updated_at();

ALTER TABLE auth_service_db.passkey_credentials ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_all_auth_passkey ON auth_service_db.passkey_credentials;
CREATE POLICY deny_all_auth_passkey
  ON auth_service_db.passkey_credentials FOR ALL
  TO public USING (false);

-- FIX: auth_service_db.refresh_tokens — el 01 la crea pero NO le activó RLS, así que
-- quedaba sin deny-all (tabla sensible) y la policy svc_auth de 009 sería inerte.
ALTER TABLE auth_service_db.refresh_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_all_auth_refresh_tokens ON auth_service_db.refresh_tokens;
CREATE POLICY deny_all_auth_refresh_tokens
  ON auth_service_db.refresh_tokens FOR ALL
  TO public USING (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- access_service_db.zk_device_commands  (cola/auditoría de comandos ZKTeco ADMS)
--   Fuente: services/access-service/src/services/zkAdmsService.js
--   insert: command_id, serial_number, command_string, estado, metadata, creado_at
--   update: estado, return_code, ejecutado_at  (por command_id)
--   query : .in(serial_number,[SN,'ALL']).eq(estado,'pending').order(creado_at)
--   ⚠ nombres de columna tal cual los usa el código: creado_at / ejecutado_at
--     (sin actualizado_en → no lleva trigger set_updated_at).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS access_service_db.zk_device_commands (
  id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  command_id     TEXT        NOT NULL UNIQUE,                 -- id de comando ZKTeco (update lo usa como clave)
  serial_number  TEXT        NOT NULL,                        -- SN de la terminal, o 'ALL' (broadcast)
  command_string TEXT        NOT NULL,                        -- comando ADMS crudo
  estado         TEXT        NOT NULL DEFAULT 'pending'
                   CHECK (estado IN ('pending','completed','failed')),
  return_code    TEXT,                                        -- código de retorno del device (al completar)
  metadata       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  creado_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ejecutado_at   TIMESTAMPTZ                                  -- se setea al recibir el resultado
);

CREATE INDEX IF NOT EXISTS idx_zk_cmd_dispatch
  ON access_service_db.zk_device_commands(serial_number, estado, creado_at);  -- despacho de pendientes

ALTER TABLE access_service_db.zk_device_commands ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_all_access_zk_commands ON access_service_db.zk_device_commands;
CREATE POLICY deny_all_access_zk_commands
  ON access_service_db.zk_device_commands FOR ALL
  TO public USING (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- fitness_service_db — 4 tablas que USA el código. El DDL viejo (02) define otros
-- nombres HUÉRFANOS (catalogo_ejercicios / rutinas_usuario / registros_nutricion)
-- que el código no toca (ver nota al final). Requiere el schema fitness_service_db
-- (lo crea 02). Nombres de columna tal cual el código (creado_at, fecha_medicion;
-- sin actualizado_en → sin trigger). usuario_id es ref LÓGICA a auth (sin FK cross-schema).
--   Fuente: exerciseModel.js · routineModel.js · progressModel.js
-- ─────────────────────────────────────────────────────────────────────────────

-- catálogo de ejercicios (solo lectura: filtros grupo_muscular/dificultad/equipamiento)
CREATE TABLE IF NOT EXISTS fitness_service_db.ejercicios (
  id             UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  nombre         VARCHAR(150) NOT NULL,
  grupo_muscular TEXT,                                    -- .in(); catálogo en muscleGroups.js
  dificultad     TEXT         CHECK (dificultad IN ('beginner','intermediate','advanced')),
  equipamiento   TEXT,
  descripcion    TEXT,                                    -- aún no la usa el código; nullable
  creado_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ejercicios_grupo ON fitness_service_db.ejercicios(grupo_muscular);

-- rutinas (cabecera): 1 usuario → N rutinas
CREATE TABLE IF NOT EXISTS fitness_service_db.rutinas (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id  UUID         NOT NULL,                      -- ref lógica a auth_service_db.usuarios
  nombre      VARCHAR(150) NOT NULL,
  descripcion TEXT,
  nivel       TEXT         NOT NULL DEFAULT 'intermediate'
                CHECK (nivel IN ('beginner','intermediate','advanced')),
  creado_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rutinas_usuario ON fitness_service_db.rutinas(usuario_id, creado_at DESC);

-- rutina_ejercicios (detalle rutina↔ejercicio con sets/reps). FKs → embed PostgREST.
CREATE TABLE IF NOT EXISTS fitness_service_db.rutina_ejercicios (
  id           UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
  rutina_id    UUID    NOT NULL REFERENCES fitness_service_db.rutinas(id)    ON DELETE CASCADE,
  ejercicio_id UUID    NOT NULL REFERENCES fitness_service_db.ejercicios(id) ON DELETE RESTRICT,
  series       INTEGER NOT NULL DEFAULT 3,
  repeticiones INTEGER NOT NULL DEFAULT 12,
  descanso_seg INTEGER NOT NULL DEFAULT 60,
  orden        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rutina_ej_rutina ON fitness_service_db.rutina_ejercicios(rutina_id);
-- Habilita el embed: rutinas → rutina_ejercicios(*, ejercicios(*)) (routineModel.js)

-- progreso_fisico (mediciones por usuario)
CREATE TABLE IF NOT EXISTS fitness_service_db.progreso_fisico (
  id               UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id       UUID         NOT NULL,                 -- ref lógica a usuarios
  peso_kg          NUMERIC(5,2) NOT NULL,
  porcentaje_grasa NUMERIC(5,2),
  masa_muscular_kg NUMERIC(5,2),
  medidas          JSONB,                                 -- { pecho, cintura, cadera, brazos, piernas }
  notas            TEXT,
  fecha_medicion   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_progreso_usuario ON fitness_service_db.progreso_fisico(usuario_id, fecha_medicion DESC);

-- RLS deny-all en las 4
ALTER TABLE fitness_service_db.ejercicios        ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.rutinas           ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.rutina_ejercicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_service_db.progreso_fisico   ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_all_fitness_ejercicios ON fitness_service_db.ejercicios;
CREATE POLICY deny_all_fitness_ejercicios ON fitness_service_db.ejercicios        FOR ALL TO public USING (false);
DROP POLICY IF EXISTS deny_all_fitness_rutinas ON fitness_service_db.rutinas;
CREATE POLICY deny_all_fitness_rutinas    ON fitness_service_db.rutinas           FOR ALL TO public USING (false);
DROP POLICY IF EXISTS deny_all_fitness_rutina_ej ON fitness_service_db.rutina_ejercicios;
CREATE POLICY deny_all_fitness_rutina_ej  ON fitness_service_db.rutina_ejercicios FOR ALL TO public USING (false);
DROP POLICY IF EXISTS deny_all_fitness_progreso ON fitness_service_db.progreso_fisico;
CREATE POLICY deny_all_fitness_progreso   ON fitness_service_db.progreso_fisico   FOR ALL TO public USING (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- COLUMNAS que el CÓDIGO escribe/lee pero el DDL no definió (features reales de
-- payment: growthRetentionWorker + subscriptionModel). Todas nullable → sin dato
-- por defecto; preservan el funcionamiento sin afectar filas existentes.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE auth_service_db.usuarios ADD COLUMN IF NOT EXISTS push_token       TEXT;  -- token FCM/APNs (push)
ALTER TABLE auth_service_db.usuarios ADD COLUMN IF NOT EXISTS objetivo_fitness TEXT;  -- contexto IA (reactivación)
ALTER TABLE auth_service_db.usuarios ADD COLUMN IF NOT EXISTS lesiones         TEXT;  -- contexto IA (reactivación)
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS razon_cancelacion          TEXT;
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS razon_fallo_pago           TEXT;
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS notificado_recuperacion_en TIMESTAMPTZ;  -- anti-spam recovery
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS notificado_inactividad_en  TIMESTAMPTZ;  -- anti-spam inactividad
-- SAFE_COLUMNS del código que el DDL de suscripciones no tenía (usa plan_precio/stripe_status/etc.):
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS monto           NUMERIC(10,2);
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS moneda          VARCHAR(3) DEFAULT 'MXN';
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS ultimo_pago_en  TIMESTAMPTZ;
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS proximo_pago_en TIMESTAMPTZ;
ALTER TABLE payment_service_db.suscripciones ADD COLUMN IF NOT EXISTS cancelado_en    TIMESTAMPTZ;

-- ─────────────────────────────────────────────────────────────────────────────
-- HUÉRFANOS en 02_fitness_service_db.sql (catalogo_ejercicios, rutinas_usuario,
-- registros_nutricion): el código NO los usa. RECOMENDACIÓN: NO crearlos —
-- al consolidar el bootstrap, recortar 02 para que solo cree el schema + enums +
-- catalogo_alimentos (que sí se usa). No se ponen DROP aquí porque en una BD
-- vacía basta con no crearlos; si ya existieran, borrarlos aparte tras confirmar.
-- ─────────────────────────────────────────────────────────────────────────────

COMMIT;
