-- =============================================================================
-- GymPro · Script de Inicialización de Esquemas
-- =============================================================================
-- Versión      : 1.0.0
-- Motor        : PostgreSQL 15+ (Supabase)
-- Patrón       : Database-per-Service simulado con schemas PostgreSQL
-- Ejecución    : SQL Editor de Supabase o psql como rol postgres/superuser
--
-- IMPORTANTE: Este script debe ejecutarse UNA SOLA VEZ en el proyecto de
--             Supabase. Para actualizaciones posteriores, usar scripts de
--             migración versionados (002_, 003_, ...) en esta misma carpeta.
--
-- DISEÑO:
--   Cada microservicio posee su propio schema. No existen FOREIGN KEY
--   cruzadas entre schemas. La consistencia entre dominios se garantiza
--   mediante eventos/API (eventual consistency), nunca por joins directos.
-- =============================================================================


-- =============================================================================
-- EXTENSIONES GLOBALES (solo se declaran una vez a nivel de base de datos)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";       -- uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";         -- gen_random_bytes(), crypt()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";          -- Índices de búsqueda de texto (GIN trigram)


-- =============================================================================
-- TIPOS ENUMERADOS COMPARTIDOS
-- Definidos en el schema public para que estén accesibles desde cualquier
-- schema sin necesidad de imports cruzados entre dominios.
-- =============================================================================

-- Nivel de actividad física del miembro
DO $$ BEGIN
  CREATE TYPE public.nivel_actividad_enum AS ENUM (
    'sedentario',
    'ligeramente_activo',
    'moderadamente_activo',
    'muy_activo',
    'extremadamente_activo'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Sexo biológico (usado en cálculos de IMC y TDEE)
DO $$ BEGIN
  CREATE TYPE public.sexo_biologico_enum AS ENUM (
    'masculino',
    'femenino',
    'no_especificado'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Estado general de un registro de acceso
DO $$ BEGIN
  CREATE TYPE public.resultado_acceso_enum AS ENUM (
    'concedido',      -- membresía activa, torniquete abierto
    'denegado',       -- membresía vencida o suspendida
    'ticket_usado',   -- pase de un solo uso canjeado
    'error_sistema'   -- fallo en validación (log para auditoría)
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Estado de una suscripción
DO $$ BEGIN
  CREATE TYPE public.estado_suscripcion_enum AS ENUM (
    'activa',
    'vencida',
    'cancelada',
    'suspendida',      -- pausa temporal (viaje, lesión)
    'pendiente_pago'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Métodos de pago aceptados
DO $$ BEGIN
  CREATE TYPE public.metodo_pago_enum AS ENUM (
    'stripe',          -- tarjeta de crédito/débito vía Stripe
    'efectivo',        -- pago en caja registrado manualmente
    'transferencia'    -- SPEI u otra transferencia bancaria
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Estado del ticket de visita
DO $$ BEGIN
  CREATE TYPE public.estado_ticket_enum AS ENUM (
    'disponible',      -- aún no ha sido canjeado
    'canjeado',        -- ya se usó para acceder
    'expirado',        -- superó la fecha límite sin usarse
    'cancelado'        -- anulado manualmente por staff
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =============================================================================
-- ██████████████████████████████████████████████████████████████████████████
-- SCHEMA: auth_service_db
-- Propietario: auth-service (Node.js en Railway)
-- Responsabilidad: Identidad, autenticación y perfil físico del miembro
-- ██████████████████████████████████████████████████████████████████████████
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth_service_db;

-- Comentario de schema para documentación en pg_catalog
COMMENT ON SCHEMA auth_service_db IS
  'Dominio de autenticación e identidad. Solo accesible por auth-service.';

-- ---------------------------------------------------------------------------
-- TABLA: auth_service_db.usuarios
-- ---------------------------------------------------------------------------
-- Contiene tanto los datos de autenticación como el perfil físico del miembro.
-- Se separan en columnas distintas para facilitar proyecciones específicas
-- (el servicio de fitness solo necesita datos físicos, no el password_hash).
--
-- NOTA DE SEGURIDAD: El campo password_hash contiene el resultado de bcrypt
-- (work factor >= 12). NUNCA se almacena la contraseña en texto plano.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auth_service_db.usuarios (

  -- ─── Identidad ────────────────────────────────────────────────────────────
  id                    UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  email                 VARCHAR(320)    NOT NULL,            -- RFC 5321: max 320 chars
  password_hash         VARCHAR(72)     NOT NULL,            -- bcrypt output: siempre 60 chars, VARCHAR(72) por margen
  telefono              VARCHAR(20),                         -- E.164 format: +521234567890
  nombre                VARCHAR(100)    NOT NULL,
  apellido_paterno      VARCHAR(100)    NOT NULL,
  apellido_materno      VARCHAR(100),

  -- ─── Perfil físico (usado por fitness-service vía API) ────────────────────
  fecha_nacimiento      DATE,
  sexo_biologico        public.sexo_biologico_enum           DEFAULT 'no_especificado',
  estatura_cm           NUMERIC(5, 1)   CHECK (estatura_cm BETWEEN 50 AND 280),   -- en centímetros
  peso_kg               NUMERIC(5, 2)   CHECK (peso_kg BETWEEN 10 AND 500),       -- en kilogramos
  nivel_actividad       public.nivel_actividad_enum          DEFAULT 'sedentario',

  -- ─── Historial clínico (sensible: encriptado en capa de aplicación) ───────
  -- Los valores se almacenan como JSONB encriptado por el auth-service antes
  -- de persistir. El schema no conoce la estructura interna.
  historial_clinico     JSONB,                               -- e.g.: {"alergias":[], "condiciones":[], "medicamentos":[]}
  contacto_emergencia   JSONB,                               -- e.g.: {"nombre":"...", "telefono":"...", "relacion":"..."}

  -- ─── Control de sesión y tokens ───────────────────────────────────────────
  -- El estado de sesión (refresh tokens) vive en auth_service_db.refresh_tokens
  -- (multi-dispositivo + reuse detection). Aquí solo bookkeeping de login.
  ultimo_login          TIMESTAMPTZ,
  intentos_fallidos     SMALLINT        NOT NULL DEFAULT 0   CHECK (intentos_fallidos >= 0),
  bloqueado_hasta       TIMESTAMPTZ,                         -- Null = no bloqueado (OWASP A7: Brute Force)

  -- ─── Verificación y estado de cuenta ─────────────────────────────────────
  email_verificado      BOOLEAN         NOT NULL DEFAULT FALSE,
  token_verificacion    UUID            DEFAULT uuid_generate_v4(),  -- se invalida al verificar
  activo                BOOLEAN         NOT NULL DEFAULT TRUE,
  rol                   VARCHAR(20)     NOT NULL DEFAULT 'miembro'   -- 'miembro' | 'staff' | 'admin'
                        CHECK (rol IN ('miembro', 'staff', 'admin')),

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  creado_en             TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  actualizado_en        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  eliminado_en          TIMESTAMPTZ                                   -- Soft delete: NULL = activo

);

-- Restricción única sobre email activo (permite re-registro tras eliminación lógica)
CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_email_activo
  ON auth_service_db.usuarios (email)
  WHERE eliminado_en IS NULL;

-- Índice principal para lookups por email (login)
CREATE INDEX IF NOT EXISTS idx_usuarios_email
  ON auth_service_db.usuarios (email);

-- Índice para soporte de búsqueda por nombre (dashboard de staff)
CREATE INDEX IF NOT EXISTS idx_usuarios_nombre_trgm
  ON auth_service_db.usuarios USING GIN (nombre gin_trgm_ops);

-- Índice para filtrar cuentas bloqueadas (tarea de limpieza del scheduler)
CREATE INDEX IF NOT EXISTS idx_usuarios_bloqueado_hasta
  ON auth_service_db.usuarios (bloqueado_hasta)
  WHERE bloqueado_hasta IS NOT NULL;

-- Trigger: actualiza automáticamente actualizado_en en cada UPDATE
CREATE OR REPLACE FUNCTION auth_service_db.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_usuarios_updated_at ON auth_service_db.usuarios;
CREATE TRIGGER trg_usuarios_updated_at
  BEFORE UPDATE ON auth_service_db.usuarios
  FOR EACH ROW EXECUTE FUNCTION auth_service_db.set_updated_at();

COMMENT ON TABLE auth_service_db.usuarios IS
  'Tabla maestra de identidad del miembro. Contiene credenciales, perfil físico y datos clínicos.';
COMMENT ON COLUMN auth_service_db.usuarios.historial_clinico IS
  'JSONB encriptado AES-256 por auth-service antes de persistir. El schema no interpreta su contenido.';
COMMENT ON COLUMN auth_service_db.usuarios.password_hash IS
  'Hash bcrypt con work factor >= 12. Nunca almacenar texto plano.';


-- ---------------------------------------------------------------------------
-- TABLA: auth_service_db.refresh_tokens
-- Refresh tokens opacos con ROTACIÓN, FAMILIAS de sesión (multi-dispositivo) y
-- REUSE DETECTION. Cada login abre una familia; cada refresh consume el token
-- actual y emite el siguiente en la misma familia. Reusar un token consumido
-- revoca la familia completa (mitiga robo). El texto plano solo vive en la
-- cookie HttpOnly del cliente; aquí solo el SHA-256.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auth_service_db.refresh_tokens (
  id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID         NOT NULL REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE,
  family_id     UUID         NOT NULL,
  token_hash    VARCHAR(64)  NOT NULL,
  is_consumed   BOOLEAN      NOT NULL DEFAULT FALSE,
  expires_at    TIMESTAMPTZ  NOT NULL,
  device_info   VARCHAR(255),
  ip_address    VARCHAR(64),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  consumed_at   TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ                                   -- NULL = vigente
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash
  ON auth_service_db.refresh_tokens (token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family_id
  ON auth_service_db.refresh_tokens (family_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id
  ON auth_service_db.refresh_tokens (user_id);

COMMENT ON TABLE auth_service_db.refresh_tokens IS
  'Refresh tokens opacos con rotación, familias de sesión (multi-dispositivo) y reuse detection.';


-- ---------------------------------------------------------------------------
-- TABLA: auth_service_db.tokens_password_reset
-- Separada de usuarios para no contaminar la tabla principal con tokens
-- temporales que se limpian frecuentemente.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auth_service_db.tokens_password_reset (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id      UUID          NOT NULL,   -- Referencia local (mismo schema)
  token_hash      VARCHAR(64)   NOT NULL,   -- SHA-256 del token enviado por email
  expira_en       TIMESTAMPTZ   NOT NULL DEFAULT (NOW() + INTERVAL '1 hour'),
  usado           BOOLEAN       NOT NULL DEFAULT FALSE,
  creado_en       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- FK local dentro del mismo schema (permitida)
  CONSTRAINT fk_tpr_usuario
    FOREIGN KEY (usuario_id) REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tpr_token_hash
  ON auth_service_db.tokens_password_reset (token_hash);

CREATE INDEX IF NOT EXISTS idx_tpr_usuario_id
  ON auth_service_db.tokens_password_reset (usuario_id);

-- Limpia tokens expirados automáticamente (requiere pg_cron en Supabase)
-- NOTA: Activar pg_cron en Supabase Dashboard → Database → Extensions
-- SELECT cron.schedule('cleanup-reset-tokens', '0 * * * *',
--   $$DELETE FROM auth_service_db.tokens_password_reset WHERE expira_en < NOW()$$);

COMMENT ON TABLE auth_service_db.tokens_password_reset IS
  'Tokens de un solo uso para restablecimiento de contraseña. TTL: 1 hora.';


-- =============================================================================
-- ██████████████████████████████████████████████████████████████████████████
-- SCHEMA: access_service_db
-- Propietario: access-service (Node.js en Railway)
-- Responsabilidad: Control de acceso físico, QR, torniquete y tickets
-- ██████████████████████████████████████████████████████████████████████████
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS access_service_db;

COMMENT ON SCHEMA access_service_db IS
  'Dominio de control de acceso físico. Solo accesible por access-service y scripts_local.';

-- ---------------------------------------------------------------------------
-- TABLA: access_service_db.historial_accesos
-- Registro inmutable de cada intento de entrada/salida al gimnasio.
-- Nunca se eliminan registros (auditoría legal y anti-fraude).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS access_service_db.historial_accesos (

  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Referencia al miembro (sin FK cruzada — se valida vía API al momento del acceso)
  usuario_id        UUID            NOT NULL,
  nombre_snapshot   VARCHAR(200)    NOT NULL,   -- Nombre del miembro al momento del acceso
                                                -- (desnormalizado intencionalmente para inmutabilidad)

  -- Datos del evento de acceso
  resultado         public.resultado_acceso_enum NOT NULL,
  tipo_acceso       VARCHAR(20)     NOT NULL DEFAULT 'qr'
                    CHECK (tipo_acceso IN ('qr', 'ticket', 'manual_staff')),

  -- Metadatos del QR presentado (sin almacenar el payload cifrado completo)
  qr_jti            UUID,                       -- JWT ID del QR (para detectar replay attacks)
  qr_emitido_en     TIMESTAMPTZ,                -- Cuándo se generó el QR que se presentó

  -- Metadatos físicos del evento
  dispositivo_id    VARCHAR(100),               -- ID del lector QR/torniquete (ej: "torniquete-01")
  ip_dispositivo    INET,                       -- IP del Raspberry Pi en LAN
  motivo_denegacion VARCHAR(255),               -- Solo si resultado = 'denegado'

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  creado_en         TIMESTAMPTZ     NOT NULL DEFAULT NOW()
  -- Sin actualizado_en: este registro es APPEND-ONLY (nunca se modifica)

);

-- Índice principal: consultas por miembro (historial de entradas en app)
CREATE INDEX IF NOT EXISTS idx_ha_usuario_id
  ON access_service_db.historial_accesos (usuario_id, creado_en DESC);

-- Índice para búsqueda de QR JTI (detección de replay attack en tiempo real)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ha_qr_jti
  ON access_service_db.historial_accesos (qr_jti)
  WHERE qr_jti IS NOT NULL;

-- Índice para reportes por rango de fecha (dashboard de staff)
CREATE INDEX IF NOT EXISTS idx_ha_creado_en
  ON access_service_db.historial_accesos (creado_en DESC);

-- Índice parcial para análisis de accesos denegados
CREATE INDEX IF NOT EXISTS idx_ha_denegados
  ON access_service_db.historial_accesos (usuario_id, creado_en DESC)
  WHERE resultado = 'denegado';

-- Protección: la tabla es append-only, no se permiten UPDATEs ni DELETEs
CREATE OR REPLACE FUNCTION access_service_db.deny_modification()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'La tabla historial_accesos es inmutable. No se permiten UPDATE ni DELETE. [AUDIT-001]';
END;
$$;

DROP TRIGGER IF EXISTS trg_ha_no_update ON access_service_db.historial_accesos;
CREATE TRIGGER trg_ha_no_update
  BEFORE UPDATE OR DELETE ON access_service_db.historial_accesos
  FOR EACH ROW EXECUTE FUNCTION access_service_db.deny_modification();

COMMENT ON TABLE access_service_db.historial_accesos IS
  'Registro de auditoría inmutable (append-only) de todos los intentos de acceso al gimnasio.';
COMMENT ON COLUMN access_service_db.historial_accesos.nombre_snapshot IS
  'Desnormalización intencional: captura el nombre en el momento del acceso para inmutabilidad histórica.';
COMMENT ON COLUMN access_service_db.historial_accesos.qr_jti IS
  'JWT ID único del QR. Permite detectar presentación doble (replay attack) con búsqueda O(log n).';


-- ---------------------------------------------------------------------------
-- TABLA: access_service_db.tickets_visitas
-- Pases de acceso de un solo uso. Alternativa a la membresía mensual.
-- Pueden comprarse en recepción (efectivo) o desde la app (Stripe).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS access_service_db.tickets_visitas (

  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Propietario del ticket (sin FK cruzada)
  usuario_id        UUID,                       -- NULL si es ticket anónimo vendido en recepción
  vendido_por       UUID,                       -- usuario_id del staff que emitió el ticket

  -- Código único del ticket
  token_codigo      VARCHAR(64)     NOT NULL,   -- Token URL-safe generado con crypto.randomBytes(32)
  token_codigo_hash VARCHAR(64)     NOT NULL,   -- SHA-256 del token (se busca por hash, nunca por plain)

  -- Control de uso
  estado            public.estado_ticket_enum   NOT NULL DEFAULT 'disponible',
  canjeado_en       TIMESTAMPTZ,               -- Timestamp exacto del canje
  acceso_id         UUID,                      -- ID del registro en historial_accesos tras el canje
                                               -- (referencia local dentro del mismo schema)
  expira_en         DATE            NOT NULL,  -- Fecha límite para usar el ticket

  -- Datos comerciales (desnormalizados del payment-service para velocidad)
  precio_pagado     NUMERIC(8, 2)  NOT NULL    CHECK (precio_pagado >= 0),
  metodo_pago       public.metodo_pago_enum    NOT NULL,
  referencia_pago   VARCHAR(255),              -- Stripe PaymentIntent ID o número de recibo en efectivo

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  creado_en         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  actualizado_en    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  notas             TEXT                        -- Observaciones del staff (ej: "regalo para visitante")

);

-- Índice de búsqueda primaria: el lector QR busca por token_codigo_hash
CREATE UNIQUE INDEX IF NOT EXISTS uq_tv_token_codigo_hash
  ON access_service_db.tickets_visitas (token_codigo_hash);

-- Índice para consultar tickets de un usuario (historial en app)
CREATE INDEX IF NOT EXISTS idx_tv_usuario_id
  ON access_service_db.tickets_visitas (usuario_id, creado_en DESC)
  WHERE usuario_id IS NOT NULL;

-- Índice para proceso de expiración automática
CREATE INDEX IF NOT EXISTS idx_tv_expiracion
  ON access_service_db.tickets_visitas (expira_en, estado)
  WHERE estado = 'disponible';

-- Trigger de actualización automática
CREATE OR REPLACE FUNCTION access_service_db.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tv_updated_at ON access_service_db.tickets_visitas;
CREATE TRIGGER trg_tv_updated_at
  BEFORE UPDATE ON access_service_db.tickets_visitas
  FOR EACH ROW EXECUTE FUNCTION access_service_db.set_updated_at();

-- Constraint: canjeado_en y acceso_id son obligatorios cuando estado = 'canjeado'
ALTER TABLE access_service_db.tickets_visitas DROP CONSTRAINT IF EXISTS chk_tv_canje_consistente;
ALTER TABLE access_service_db.tickets_visitas
  ADD CONSTRAINT chk_tv_canje_consistente
  CHECK (
    (estado = 'canjeado' AND canjeado_en IS NOT NULL AND acceso_id IS NOT NULL)
    OR estado != 'canjeado'
  );

COMMENT ON TABLE access_service_db.tickets_visitas IS
  'Pases de acceso de un solo uso. Gestionados por access-service. Referencia a historial_accesos tras canje.';
COMMENT ON COLUMN access_service_db.tickets_visitas.token_codigo IS
  'Token en texto plano: solo se muestra al comprador. Nunca se almacena en logs.';
COMMENT ON COLUMN access_service_db.tickets_visitas.token_codigo_hash IS
  'SHA-256 del token_codigo. El sistema siempre busca y compara por hash, nunca por texto plano.';


-- =============================================================================
-- ██████████████████████████████████████████████████████████████████████████
-- SCHEMA: payment_service_db
-- Propietario: payment-service (Node.js en Railway)
-- Responsabilidad: Suscripciones, pagos y estado financiero del miembro
-- ██████████████████████████████████████████████████████████████████████████
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS payment_service_db;

COMMENT ON SCHEMA payment_service_db IS
  'Dominio de pagos y suscripciones. Solo accesible por payment-service.';

-- ---------------------------------------------------------------------------
-- TABLA: payment_service_db.suscripciones
-- Membresía recurrente del miembro. Puede ser gestionada por Stripe
-- (renovación automática) o de forma manual por staff (pago en efectivo).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS payment_service_db.suscripciones (

  id                        UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Propietario (sin FK cruzada a auth_service_db)
  usuario_id                UUID            NOT NULL,

  -- ─── Configuración del plan ───────────────────────────────────────────────
  plan_nombre               VARCHAR(100)    NOT NULL,  -- 'Mensual Estándar', 'Trimestral', etc.
  plan_precio               NUMERIC(8, 2)   NOT NULL   CHECK (plan_precio >= 0),
  plan_duracion_dias        SMALLINT        NOT NULL   CHECK (plan_duracion_dias > 0),
                                                       -- 30, 90, 365, etc.

  -- ─── Vigencia ─────────────────────────────────────────────────────────────
  -- CAMPO CRÍTICO: La fecha exacta de expiración. Indexada para lookups de acceso.
  valido_desde              DATE            NOT NULL DEFAULT CURRENT_DATE,
  valido_hasta              DATE            NOT NULL,
  estado                    public.estado_suscripcion_enum NOT NULL DEFAULT 'activa',

  -- ─── Integración con Stripe (solo cuando metodo_pago = 'stripe') ──────────
  stripe_customer_id        VARCHAR(50),              -- cus_XXXXXXXXXXXX
  stripe_subscription_id    VARCHAR(50),              -- sub_XXXXXXXXXXXX (suscripción recurrente)
  stripe_price_id           VARCHAR(50),              -- price_XXXXXXXXXXXX (plan en Stripe)
  stripe_payment_method_id  VARCHAR(50),              -- pm_XXXXXXXXXXXX (tarjeta guardada)
  stripe_status             VARCHAR(30),              -- 'active', 'past_due', 'canceled', etc.
                                                      -- Refleja el estado reportado por Stripe

  -- ─── Pago ─────────────────────────────────────────────────────────────────
  metodo_pago               public.metodo_pago_enum  NOT NULL,
  renovacion_automatica     BOOLEAN         NOT NULL DEFAULT TRUE,
                                                      -- FALSE para pagos manuales en efectivo

  -- ─── Razón de cancelación / suspensión (opcional) ─────────────────────────
  motivo_cambio_estado      TEXT,                     -- 'Solicitud del cliente', 'Pago fallido', etc.
  suspendido_desde          DATE,
  suspendido_hasta          DATE,

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  registrado_por            UUID,                     -- usuario_id del staff (si fue manual)
  creado_en                 TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  actualizado_en            TIMESTAMPTZ     NOT NULL DEFAULT NOW()

);

-- Índice principal: acceso en tiempo real → busca si el miembro tiene membresía activa vigente
CREATE INDEX IF NOT EXISTS idx_sus_usuario_estado_vigencia
  ON payment_service_db.suscripciones (usuario_id, estado, valido_hasta DESC);

-- Índice para el proceso de renovación automática (scheduler diario)
CREATE INDEX IF NOT EXISTS idx_sus_por_vencer
  ON payment_service_db.suscripciones (valido_hasta, estado)
  WHERE estado IN ('activa', 'suspendida');

-- Índice de lookup por Stripe subscription ID (para webhooks de Stripe)
CREATE UNIQUE INDEX IF NOT EXISTS uq_sus_stripe_subscription_id
  ON payment_service_db.suscripciones (stripe_subscription_id)
  WHERE stripe_subscription_id IS NOT NULL;

-- Índice por Stripe customer ID (para operaciones de billing)
CREATE INDEX IF NOT EXISTS idx_sus_stripe_customer_id
  ON payment_service_db.suscripciones (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

-- Constraint: si metodo_pago = 'stripe', stripe_customer_id es obligatorio
ALTER TABLE payment_service_db.suscripciones DROP CONSTRAINT IF EXISTS chk_sus_stripe_campos;
ALTER TABLE payment_service_db.suscripciones
  ADD CONSTRAINT chk_sus_stripe_campos
  CHECK (
    (metodo_pago = 'stripe' AND stripe_customer_id IS NOT NULL)
    OR metodo_pago != 'stripe'
  );

-- Constraint: valido_hasta siempre debe ser posterior a valido_desde
ALTER TABLE payment_service_db.suscripciones DROP CONSTRAINT IF EXISTS chk_sus_fechas_coherentes;
ALTER TABLE payment_service_db.suscripciones
  ADD CONSTRAINT chk_sus_fechas_coherentes
  CHECK (valido_hasta > valido_desde);

-- Constraint: suspendido_hasta debe ser posterior a suspendido_desde
ALTER TABLE payment_service_db.suscripciones DROP CONSTRAINT IF EXISTS chk_sus_suspension_coherente;
ALTER TABLE payment_service_db.suscripciones
  ADD CONSTRAINT chk_sus_suspension_coherente
  CHECK (
    (suspendido_desde IS NULL AND suspendido_hasta IS NULL)
    OR (suspendido_desde IS NOT NULL AND suspendido_hasta IS NOT NULL AND suspendido_hasta > suspendido_desde)
  );

-- Trigger de actualización automática
CREATE OR REPLACE FUNCTION payment_service_db.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sus_updated_at ON payment_service_db.suscripciones;
CREATE TRIGGER trg_sus_updated_at
  BEFORE UPDATE ON payment_service_db.suscripciones
  FOR EACH ROW EXECUTE FUNCTION payment_service_db.set_updated_at();

COMMENT ON TABLE payment_service_db.suscripciones IS
  'Membresías activas e históricas del miembro. Fuente de verdad para determinar si un miembro puede acceder.';
COMMENT ON COLUMN payment_service_db.suscripciones.valido_hasta IS
  'CRÍTICO: Fecha exacta de expiración. Indexada. access-service la consulta vía API para validar acceso.';
COMMENT ON COLUMN payment_service_db.suscripciones.stripe_status IS
  'Estado reportado por Stripe en webhooks. Puede diferir del campo estado interno durante sincronización.';


-- ---------------------------------------------------------------------------
-- TABLA: payment_service_db.pagos
-- Registro histórico de cada transacción de pago individual.
-- Una suscripción puede tener múltiples pagos (renovaciones mensuales).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS payment_service_db.pagos (

  id                    UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Referencia local (mismo schema — FK permitida)
  suscripcion_id        UUID            NOT NULL,
  usuario_id            UUID            NOT NULL,   -- Desnormalizado para queries directas

  -- Datos de la transacción
  monto                 NUMERIC(8, 2)   NOT NULL   CHECK (monto > 0),
  moneda                CHAR(3)         NOT NULL DEFAULT 'MXN',  -- ISO 4217
  metodo_pago           public.metodo_pago_enum NOT NULL,
  estado_pago           VARCHAR(30)     NOT NULL DEFAULT 'completado'
                        CHECK (estado_pago IN ('completado', 'fallido', 'reembolsado', 'pendiente')),

  -- Integración Stripe
  stripe_payment_intent_id  VARCHAR(50),          -- pi_XXXXXXXXXXXX
  stripe_invoice_id         VARCHAR(50),          -- in_XXXXXXXXXXXX
  stripe_charge_id          VARCHAR(50),          -- ch_XXXXXXXXXXXX

  -- Datos de recibo (para efectivo/transferencia)
  numero_recibo         VARCHAR(50),              -- Folio generado por el sistema de caja
  notas_staff           TEXT,                     -- Observaciones del cajero

  -- Período que cubre este pago
  periodo_desde         DATE            NOT NULL,
  periodo_hasta         DATE            NOT NULL,

  -- ─── Auditoría ────────────────────────────────────────────────────────────
  registrado_por        UUID,                     -- staff que registró el pago manual
  creado_en             TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_pagos_suscripcion
    FOREIGN KEY (suscripcion_id) REFERENCES payment_service_db.suscripciones(id)
    ON DELETE RESTRICT   -- No eliminar suscripción si tiene pagos registrados
);

CREATE INDEX IF NOT EXISTS idx_pagos_usuario_id
  ON payment_service_db.pagos (usuario_id, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_pagos_suscripcion_id
  ON payment_service_db.pagos (suscripcion_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pagos_stripe_payment_intent
  ON payment_service_db.pagos (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

COMMENT ON TABLE payment_service_db.pagos IS
  'Historial de transacciones. Cada renovación de suscripción genera un registro aquí.';


-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- Supabase expone los schemas vía PostgREST. Sin RLS, cualquier cliente con
-- la anon/service key tendría acceso total. Bloqueamos todo y abrimos solo
-- lo necesario para cada service role.
-- =============================================================================

-- Habilitar RLS en todas las tablas
ALTER TABLE auth_service_db.usuarios                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_service_db.tokens_password_reset     ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_service_db.historial_accesos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_service_db.tickets_visitas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_service_db.suscripciones          ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_service_db.pagos                  ENABLE ROW LEVEL SECURITY;

-- ─── POLÍTICA BASE: Denegar todo por defecto ──────────────────────────────
-- Los microservicios se conectan con la SERVICE_ROLE_KEY de Supabase,
-- que bypasea RLS por diseño. Las políticas siguientes son para el rol
-- 'authenticated' (clientes directos de Supabase, si se usan en el futuro).

-- Por ahora, bloqueamos acceso público total. Solo service_role tiene acceso.
CREATE POLICY deny_all_auth_usuarios
  ON auth_service_db.usuarios FOR ALL
  TO public USING (false);

CREATE POLICY deny_all_auth_tokens
  ON auth_service_db.tokens_password_reset FOR ALL
  TO public USING (false);

CREATE POLICY deny_all_access_historial
  ON access_service_db.historial_accesos FOR ALL
  TO public USING (false);

CREATE POLICY deny_all_access_tickets
  ON access_service_db.tickets_visitas FOR ALL
  TO public USING (false);

CREATE POLICY deny_all_payment_suscripciones
  ON payment_service_db.suscripciones FOR ALL
  TO public USING (false);

CREATE POLICY deny_all_payment_pagos
  ON payment_service_db.pagos FOR ALL
  TO public USING (false);


-- =============================================================================
-- GRANTS DE PERMISOS POR ROL DE SERVICIO
-- En Supabase, crear un rol por microservicio permite auditoría granular.
-- Ejecutar en Supabase Dashboard → Database → Roles (o SQL Editor como superuser).
-- =============================================================================

-- NOTA: Descomentar y ejecutar manualmente en Supabase SQL Editor.
-- Los nombres de rol deben coincidir exactamente con los configurados
-- en las variables de entorno SUPABASE_DB_ROLE de cada microservicio.

/*

-- Rol para auth-service
CREATE ROLE auth_service_role WITH LOGIN PASSWORD 'CAMBIAR_POR_PASSWORD_SEGURO';
GRANT USAGE ON SCHEMA auth_service_db TO auth_service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth_service_db TO auth_service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth_service_db TO auth_service_role;

-- Rol para access-service
CREATE ROLE access_service_role WITH LOGIN PASSWORD 'CAMBIAR_POR_PASSWORD_SEGURO';
GRANT USAGE ON SCHEMA access_service_db TO access_service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA access_service_db TO access_service_role;
-- Solo lectura en auth para verificar nombre del miembro (via view, no acceso directo)
GRANT USAGE ON SCHEMA auth_service_db TO access_service_role;
GRANT SELECT ON auth_service_db.usuarios TO access_service_role;

-- Rol para payment-service
CREATE ROLE payment_service_role WITH LOGIN PASSWORD 'CAMBIAR_POR_PASSWORD_SEGURO';
GRANT USAGE ON SCHEMA payment_service_db TO payment_service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA payment_service_db TO payment_service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA payment_service_db TO payment_service_role;

*/


-- =============================================================================
-- VERIFICACIÓN FINAL
-- =============================================================================
-- Ejecuta este bloque para confirmar que todos los objetos fueron creados.
-- Debería retornar 6 tablas y 3 schemas (además de public).

DO $$
DECLARE
  tabla_count INT;
  schema_count INT;
BEGIN
  SELECT COUNT(*) INTO tabla_count
  FROM information_schema.tables
  WHERE table_schema IN ('auth_service_db', 'access_service_db', 'payment_service_db')
    AND table_type = 'BASE TABLE';

  SELECT COUNT(*) INTO schema_count
  FROM information_schema.schemata
  WHERE schema_name IN ('auth_service_db', 'access_service_db', 'payment_service_db');

  RAISE NOTICE '✅ Schemas creados: % / 3 esperados', schema_count;
  RAISE NOTICE '✅ Tablas creadas:  % / 6 esperadas', tabla_count;

  IF tabla_count < 6 OR schema_count < 3 THEN
    RAISE EXCEPTION '❌ Verificación fallida. Revisar errores en la ejecución del script.';
  END IF;
END;
$$;
