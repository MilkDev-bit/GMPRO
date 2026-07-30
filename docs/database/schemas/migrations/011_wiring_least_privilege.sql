-- =============================================================================
-- 011 · WIRING de los roles de mínimo privilegio (post-009)
-- Fecha: 2026-07-29 · Idempotente · Ver docs/database/WIRING-least-privilege.md
-- =============================================================================
-- Habilita el USO real de los roles svc_* según el enfoque híbrido:
--   • JWT scopeado (fitness, access): PostgREST necesita poder SET ROLE → GRANT a
--     authenticator. Además, RLS ya se aplica → cubrir cruces de schema faltantes.
--   • pg directo (payment, auth): fijar search_path del rol para no calificar tablas.
-- Ejecutar como postgres tras 009 + bootstrap. Seguro de re-ejecutar.
-- =============================================================================

BEGIN;

-- ── JWT scopeado: permitir a PostgREST cambiar a estos roles ─────────────────
GRANT svc_fitness TO authenticator;
GRANT svc_access  TO authenticator;

-- ── Cruce faltante de access → payment (fallback directo a suscripciones) ────
-- access-service lee payment_service_db.suscripciones como respaldo si la API HTTP
-- de payment falla (para no bloquear el torniquete). 009 no lo cubría.
GRANT USAGE ON SCHEMA payment_service_db TO svc_access;
GRANT SELECT (usuario_id, estado, valido_hasta)
  ON payment_service_db.suscripciones TO svc_access;
DROP POLICY IF EXISTS svc_access_ro_sub ON payment_service_db.suscripciones;
CREATE POLICY svc_access_ro_sub
  ON payment_service_db.suscripciones FOR SELECT TO svc_access USING (true);

-- ── pg directo (payment): columnas extra de usuarios que lee el worker ───────
-- 009 concedió a svc_payment un SELECT por columnas sobre auth.usuarios; el
-- growthRetentionWorker también lee push_token/objetivo_fitness/lesiones (010).
GRANT SELECT (push_token, objetivo_fitness, lesiones)
  ON auth_service_db.usuarios TO svc_payment;

-- ── pg directo: search_path por rol (evita calificar cada tabla en el SQL) ────
-- Los cruces a OTRO schema se calificarán explícitamente en el SQL de los modelos.
ALTER ROLE svc_payment SET search_path TO payment_service_db;
ALTER ROLE svc_auth    SET search_path TO auth_service_db;

COMMIT;

-- =============================================================================
-- NOTA: cuando los 5 servicios usen su rol, revocar los privilegios de rutina de
-- service_role y rotar su clave (dejarlo solo para administración puntual).
-- =============================================================================
