-- =============================================================================
-- Migración: expiración SERVER-SIDE del refresh token
-- Fecha: 2026-07-23
-- Servicio: auth-service
-- =============================================================================
-- CONTEXTO
--   Antes, el refresh token solo tenía vida útil en el maxAge de la cookie
--   (lado cliente). Server-side, el `refresh_token_hash` era válido de forma
--   INDEFINIDA hasta rotarse/sobrescribirse: un hash exfiltrado de la DB o una
--   cookie robada podía canjearse para siempre. Esta columna hace del servidor
--   la autoridad: el endpoint /refresh rechaza (401) y revoca el hash si venció.
--
-- IDEMPOTENTE: usa IF NOT EXISTS. Seguro de re-ejecutar.
-- Ajusta el schema/qualified name si tu tabla `usuarios` vive en otro esquema.
-- =============================================================================

ALTER TABLE auth_service_db.usuarios
  ADD COLUMN IF NOT EXISTS refresh_token_expires_at TIMESTAMPTZ;

COMMENT ON COLUMN auth_service_db.usuarios.refresh_token_expires_at IS
  'Expiración server-side del refresh token (autoridad, no la cookie). NULL = sin sesión activa o fila legacy (se acepta hasta el próximo login, que la poblará).';

-- Nota: la búsqueda en /refresh filtra por refresh_token_hash. Si aún no existe
-- un índice para esa columna, conviene crearlo para evitar full scans:
--   CREATE INDEX IF NOT EXISTS idx_usuarios_refresh_token_hash
--     ON usuarios (refresh_token_hash) WHERE refresh_token_hash IS NOT NULL;
