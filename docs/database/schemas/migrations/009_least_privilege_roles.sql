-- =============================================================================
-- MIGRACIÓN 009 (CLD-1): roles Postgres de MÍNIMO PRIVILEGIO por servicio
-- Fecha: 2026-07-29 · Alcance: los 5 microservicios · Idempotente
-- =============================================================================
-- ⚠ EJECUCIÓN: por psql con variables -v (NO en el SQL Editor de Supabase, que
--   no interpola ':VAR'). Ver 009_least_privilege_roles.RUNBOOK.md.
--
--   psql "$STAGING_DB_URL" \
--     -v AUTH_DB_PASSWORD="$AUTH_DB_PASSWORD" \
--     -v ACCESS_DB_PASSWORD="$ACCESS_DB_PASSWORD" \
--     -v PAYMENT_DB_PASSWORD="$PAYMENT_DB_PASSWORD" \
--     -v FITNESS_DB_PASSWORD="$FITNESS_DB_PASSWORD" \
--     -f 009_least_privilege_roles.sql   (ai-service no lleva rol: es apátrida)
--
-- ANTES: corre 009_least_privilege_roles.PREFLIGHT.sql y confirma nombres/RLS.
-- DESPUÉS: corre 009_least_privilege_roles.VERIFY.sql.
-- REVERTIR: 009_least_privilege_roles.ROLLBACK.sql.
--
-- ⚠ ESTO NO CAMBIA CÓMO CONECTA LA APP. Hoy los servicios usan PostgREST con
--   SERVICE_ROLE_KEY (bypassa RLS). Estos roles svc_* solo se USAN cuando cada
--   servicio migre a conexión pg directa con su credencial (o JWT con role
--   scopeado). 009 crea y valida el modelo; el cableado de la app es aparte.
--
-- MODELO: cada servicio recibe `svc_<nombre>` (LOGIN, NOBYPASSRLS) con USAGE +
--   SELECT/INSERT/UPDATE/DELETE mínimos sobre SUS tablas y EXECUTE sobre SUS
--   funciones. Como las tablas tienen RLS deny-all (public → false), se añade una
--   policy permisiva `TO svc_<rol>` por tabla (public→false OR rol→true).
-- Idempotente: roles con guarda, policies con DROP ... IF EXISTS, grants repetibles.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- 1) auth-service  → schema auth_service_db
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_auth') THEN
  CREATE ROLE svc_auth LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS; END IF; END $$;
ALTER ROLE svc_auth WITH PASSWORD :'AUTH_DB_PASSWORD';   -- fuera del DO: psql interpola aquí

GRANT USAGE ON SCHEMA auth_service_db TO svc_auth;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  auth_service_db.usuarios,
  auth_service_db.passkey_credentials,
  auth_service_db.tokens_password_reset,
  auth_service_db.refresh_tokens
  TO svc_auth;
GRANT EXECUTE ON FUNCTION auth_service_db.assign_pin_terminal(UUID) TO svc_auth;

DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.usuarios;
CREATE POLICY svc_auth_rw ON auth_service_db.usuarios              FOR ALL TO svc_auth USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.passkey_credentials;
CREATE POLICY svc_auth_rw ON auth_service_db.passkey_credentials   FOR ALL TO svc_auth USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.tokens_password_reset;
CREATE POLICY svc_auth_rw ON auth_service_db.tokens_password_reset FOR ALL TO svc_auth USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.refresh_tokens;
CREATE POLICY svc_auth_rw ON auth_service_db.refresh_tokens        FOR ALL TO svc_auth USING (true) WITH CHECK (true);

-- =============================================================================
-- 2) access-service → access_service_db + LECTURA de auth_service_db.usuarios
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_access') THEN
  CREATE ROLE svc_access LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS; END IF; END $$;
ALTER ROLE svc_access WITH PASSWORD :'ACCESS_DB_PASSWORD';

GRANT USAGE ON SCHEMA access_service_db TO svc_access;
GRANT SELECT, INSERT, UPDATE ON
  access_service_db.historial_accesos,
  access_service_db.qr_nonces_consumidos,
  access_service_db.tickets_visitas,
  access_service_db.zk_device_commands
  TO svc_access;
-- Cruce mínimo: valida al socio (SOLO lectura de columnas necesarias).
GRANT USAGE ON SCHEMA auth_service_db TO svc_access;
GRANT SELECT (id, activo, nombre, apellido_paterno, pin_terminal, eliminado_en)
  ON auth_service_db.usuarios TO svc_access;

DROP POLICY IF EXISTS svc_access_rw ON access_service_db.historial_accesos;
CREATE POLICY svc_access_rw ON access_service_db.historial_accesos     FOR ALL TO svc_access USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.qr_nonces_consumidos;
CREATE POLICY svc_access_rw ON access_service_db.qr_nonces_consumidos  FOR ALL TO svc_access USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.tickets_visitas;
CREATE POLICY svc_access_rw ON access_service_db.tickets_visitas       FOR ALL TO svc_access USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.zk_device_commands;
CREATE POLICY svc_access_rw ON access_service_db.zk_device_commands    FOR ALL TO svc_access USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_access_ro ON auth_service_db.usuarios;
CREATE POLICY svc_access_ro ON auth_service_db.usuarios               FOR SELECT TO svc_access USING (true);

-- =============================================================================
-- 3) payment-service → payment_service_db + LECTURAS cruzadas
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_payment') THEN
  CREATE ROLE svc_payment LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS; END IF; END $$;
ALTER ROLE svc_payment WITH PASSWORD :'PAYMENT_DB_PASSWORD';

GRANT USAGE ON SCHEMA payment_service_db TO svc_payment;
GRANT SELECT, INSERT, UPDATE ON
  payment_service_db.suscripciones,
  payment_service_db.historial_pagos,
  payment_service_db.ofertas,
  payment_service_db.webhook_events_procesados
  TO svc_payment;
-- EXECUTE sobre las funciones del PROPIO schema (registrar_pago_efectivo,
-- increment_offer_usage) sin enumerar firmas exactas.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA payment_service_db TO svc_payment;
-- Cruces de lectura + PIN biométrico.
GRANT USAGE ON SCHEMA auth_service_db, access_service_db TO svc_payment;
GRANT SELECT (id, activo, nombre, apellido_paterno, email, pin_terminal, eliminado_en)
  ON auth_service_db.usuarios TO svc_payment;
GRANT EXECUTE ON FUNCTION auth_service_db.assign_pin_terminal(UUID) TO svc_payment;
GRANT SELECT ON access_service_db.historial_accesos TO svc_payment;

DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.suscripciones;
CREATE POLICY svc_payment_rw ON payment_service_db.suscripciones            FOR ALL TO svc_payment USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.historial_pagos;
CREATE POLICY svc_payment_rw ON payment_service_db.historial_pagos          FOR ALL TO svc_payment USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.ofertas;
CREATE POLICY svc_payment_rw ON payment_service_db.ofertas                  FOR ALL TO svc_payment USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.webhook_events_procesados;
CREATE POLICY svc_payment_rw ON payment_service_db.webhook_events_procesados FOR ALL TO svc_payment USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_payment_ro_u ON auth_service_db.usuarios;
CREATE POLICY svc_payment_ro_u ON auth_service_db.usuarios                  FOR SELECT TO svc_payment USING (true);
DROP POLICY IF EXISTS svc_payment_ro_h ON access_service_db.historial_accesos;
CREATE POLICY svc_payment_ro_h ON access_service_db.historial_accesos       FOR SELECT TO svc_payment USING (true);

-- =============================================================================
-- 4) fitness-service → fitness_service_db
--    ⚠ 'ejercicios': confirmar nombre real en el PREFLIGHT (ejercicios vs
--      catalogo_ejercicios) y ajustar tabla + policy svc_fitness_ro_e si difiere.
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_fitness') THEN
  CREATE ROLE svc_fitness LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS; END IF; END $$;
ALTER ROLE svc_fitness WITH PASSWORD :'FITNESS_DB_PASSWORD';

GRANT USAGE ON SCHEMA fitness_service_db TO svc_fitness;
GRANT SELECT ON fitness_service_db.catalogo_alimentos TO svc_fitness;   -- catálogo: solo lectura
GRANT SELECT ON fitness_service_db.ejercicios TO svc_fitness;           -- catálogo: solo lectura
GRANT SELECT, INSERT, UPDATE, DELETE ON
  fitness_service_db.progreso_fisico,
  fitness_service_db.rutinas,
  fitness_service_db.rutina_ejercicios
  TO svc_fitness;

DROP POLICY IF EXISTS svc_fitness_ro_a ON fitness_service_db.catalogo_alimentos;
CREATE POLICY svc_fitness_ro_a ON fitness_service_db.catalogo_alimentos FOR SELECT TO svc_fitness USING (true);
DROP POLICY IF EXISTS svc_fitness_ro_e ON fitness_service_db.ejercicios;
CREATE POLICY svc_fitness_ro_e ON fitness_service_db.ejercicios         FOR SELECT TO svc_fitness USING (true);
DROP POLICY IF EXISTS svc_fitness_rw_p ON fitness_service_db.progreso_fisico;
CREATE POLICY svc_fitness_rw_p ON fitness_service_db.progreso_fisico    FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_fitness_rw_r ON fitness_service_db.rutinas;
CREATE POLICY svc_fitness_rw_r ON fitness_service_db.rutinas            FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS svc_fitness_rw_re ON fitness_service_db.rutina_ejercicios;
CREATE POLICY svc_fitness_rw_re ON fitness_service_db.rutina_ejercicios FOR ALL TO svc_fitness USING (true) WITH CHECK (true);

-- =============================================================================
-- 5) ai-service → SIN schema ni rol. ai-service es APÁTRIDA en Postgres: el
--    historial de chat llega del cliente, la caché es Redis y el health-check
--    tolera que la tabla no exista (42P01). No se crea ai_service_db ni svc_ai.
--    Ver docs/database/SCHEMA-RECONCILIATION.md. (Antes usaba AI_DB_PASSWORD.)
-- =============================================================================

COMMIT;

-- =============================================================================
-- ROTACIÓN / SALIDA (fuera de esta transacción, cuando la app YA use los roles):
--   • Revocar los privilegios amplios de service_role del uso de rutina y ROTAR
--     su clave; mantener service_role solo para administración puntual.
--   • Rotación de passwords svc_*: cada corrida de 009 hace ALTER ROLE ... PASSWORD
--     con el valor de las -v actuales, así que re-ejecutar con nuevas -v ROTA la clave.
-- =============================================================================
