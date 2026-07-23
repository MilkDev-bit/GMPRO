-- =============================================================================
-- Migración: tabla dedicada refresh_tokens con FAMILIAS + reuse detection
-- Fecha: 2026-07-23
-- Servicio: auth-service
-- =============================================================================
-- MOTIVACIÓN
--   El modelo anterior guardaba UN solo refresh_token_hash en usuarios, lo que
--   impedía (a) multi-dispositivo y (b) detección de reuse/replay. Este modelo
--   dedicado soporta N sesiones concurrentes por usuario (una "familia" por
--   dispositivo/sesión) y permite la política de seguridad estricta: si se
--   reusa un token ya consumido → se revoca TODA la familia (mitiga robo).
--
--   Reemplaza a la migración 2026-07-23_refresh_token_server_side_expiry.sql,
--   cuya columna usuarios.refresh_token_expires_at queda EN DESUSO (inofensiva).
--
-- IDEMPOTENTE. Ajusta el esquema calificado si usuarios vive en otro schema.
-- =============================================================================

CREATE TABLE IF NOT EXISTS auth_service_db.refresh_tokens (
  id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID         NOT NULL REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE,
  -- Familia de sesión: todos los tokens rotados de una misma sesión/dispositivo
  -- comparten family_id. Revocar la familia mata la sesión completa.
  family_id     UUID         NOT NULL,
  -- SHA-256 (hex) del token opaco. El texto plano nunca se almacena.
  token_hash    VARCHAR(64)  NOT NULL,
  -- Marca de "ya usado". La rotación consume el token actual y emite el siguiente.
  -- Si llega un token con is_consumed=TRUE → REUSE → revocar familia.
  is_consumed   BOOLEAN      NOT NULL DEFAULT FALSE,
  -- Autoridad server-side de expiración (no la cookie).
  expires_at    TIMESTAMPTZ  NOT NULL,
  -- Metadatos de sesión (auditoría / listado de dispositivos activos).
  device_info   VARCHAR(255),
  ip_address    VARCHAR(64),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  consumed_at   TIMESTAMPTZ,
  -- Revocación: familia completa (reuse/logout) o individual. NULL = vigente.
  revoked_at    TIMESTAMPTZ
);

-- token_hash se busca en cada /refresh: único e indexado.
CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash
  ON auth_service_db.refresh_tokens (token_hash);

-- Revocación por familia y por usuario, y listado de sesiones activas.
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family_id ON auth_service_db.refresh_tokens (family_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id   ON auth_service_db.refresh_tokens (user_id);

COMMENT ON TABLE auth_service_db.refresh_tokens IS
  'Refresh tokens opacos con rotación, familias de sesión (multi-dispositivo) y reuse detection. El texto plano vive solo en la cookie HttpOnly del cliente.';

-- Limpieza de columnas legacy en usuarios (ya no se usan; el estado de sesión
-- vive en refresh_tokens). Seguras de dropear: ningún flujo las lee tras el refactor.
ALTER TABLE auth_service_db.usuarios DROP COLUMN IF EXISTS refresh_token_hash;
ALTER TABLE auth_service_db.usuarios DROP COLUMN IF EXISTS refresh_token_expires_at;
