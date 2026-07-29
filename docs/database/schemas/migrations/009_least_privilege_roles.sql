-- =============================================================================
-- MIGRACIÓN 009 (PROPUESTA — CLD-1): roles Postgres de MÍNIMO PRIVILEGIO por servicio
-- =============================================================================
-- ⚠ NO EJECUTAR EN PRODUCCIÓN SIN REVISIÓN. Entregable para ejecución MANUAL.
--
-- Objetivo: retirar la credencial God-mode `service_role` (bypassa RLS, acceso
-- total a todos los schemas) del uso rutinario y darle a cada microservicio un
-- rol con permisos SOLO sobre las tablas/funciones que realmente usa.
--
-- MODELO: cada servicio recibe un rol `svc_<nombre>` con:
--   • USAGE sobre el/los schema(s) que consume.
--   • SELECT/INSERT/UPDATE/DELETE mínimos sobre SUS tablas.
--   • EXECUTE sobre SUS funciones.
--   • Cruces de schema (SELECT acotado) donde el servicio lee datos de otro dominio.
-- Como las tablas tienen RLS deny-all (`FOR ALL TO public USING (false)`) y estos
-- roles NO son service_role (no bypassan RLS), se añade una POLICY permisiva
-- `TO svc_<rol>` por tabla para que el rol pueda operar (public→false OR rol→true).
--
-- ⚠ NOMBRES DE TABLA: se usan los nombres tal como los CONSULTAN los modelos
--   (autoritativo de lo que cada servicio accede). Confírmalos contra el schema
--   REAL antes de aplicar — los docs de esquema pueden estar desincronizados
--   (p. ej. ejercicios vs catalogo_ejercicios). Ajusta según information_schema.
--
-- Los mapas de tablas provienen de `grep .from()/.rpc()` por servicio (2026-07-24).
-- =============================================================================

-- Helper conceptual (repetido por rol/tabla): política permisiva para el rol.
--   CREATE POLICY svc_rw ON <schema>.<tabla> FOR ALL TO <rol> USING (true) WITH CHECK (true);

-- =============================================================================
-- 1) auth-service  → schema auth_service_db
--    Tablas: usuarios, passkey_credentials, tokens_password_reset, refresh_tokens
--    Funciones: assign_pin_terminal
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_auth') THEN
  CREATE ROLE svc_auth LOGIN PASSWORD :'AUTH_DB_PASSWORD' NOBYPASSRLS; END IF; END $$;

GRANT USAGE ON SCHEMA auth_service_db TO svc_auth;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  auth_service_db.usuarios,
  auth_service_db.passkey_credentials,
  auth_service_db.tokens_password_reset,
  auth_service_db.refresh_tokens
  TO svc_auth;
GRANT EXECUTE ON FUNCTION auth_service_db.assign_pin_terminal(UUID) TO svc_auth;

CREATE POLICY svc_auth_rw ON auth_service_db.usuarios              FOR ALL TO svc_auth USING (true) WITH CHECK (true);
CREATE POLICY svc_auth_rw ON auth_service_db.passkey_credentials   FOR ALL TO svc_auth USING (true) WITH CHECK (true);
CREATE POLICY svc_auth_rw ON auth_service_db.tokens_password_reset FOR ALL TO svc_auth USING (true) WITH CHECK (true);
CREATE POLICY svc_auth_rw ON auth_service_db.refresh_tokens        FOR ALL TO svc_auth USING (true) WITH CHECK (true);

-- =============================================================================
-- 2) access-service → schema access_service_db + LECTURA de auth_service_db.usuarios
--    Tablas propias: historial_accesos, qr_nonces_consumidos, tickets_visitas, zk_device_commands
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_access') THEN
  CREATE ROLE svc_access LOGIN PASSWORD :'ACCESS_DB_PASSWORD' NOBYPASSRLS; END IF; END $$;

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

CREATE POLICY svc_access_rw ON access_service_db.historial_accesos     FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_rw ON access_service_db.qr_nonces_consumidos  FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_rw ON access_service_db.tickets_visitas       FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_rw ON access_service_db.zk_device_commands    FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_ro ON auth_service_db.usuarios                FOR SELECT TO svc_access USING (true);

-- =============================================================================
-- 3) payment-service → schema payment_service_db + LECTURAS cruzadas
--    Propias: suscripciones, historial_pagos, ofertas, webhook_events_procesados
--    Funciones: registrar_pago_efectivo, increment_offer_usage
--    Cruces: auth_service_db.usuarios (biometría), access_service_db.historial_accesos,
--            auth_service_db.assign_pin_terminal
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_payment') THEN
  CREATE ROLE svc_payment LOGIN PASSWORD :'PAYMENT_DB_PASSWORD' NOBYPASSRLS; END IF; END $$;

GRANT USAGE ON SCHEMA payment_service_db TO svc_payment;
GRANT SELECT, INSERT, UPDATE ON
  payment_service_db.suscripciones,
  payment_service_db.historial_pagos,
  payment_service_db.ofertas,
  payment_service_db.webhook_events_procesados
  TO svc_payment;
-- EXECUTE sobre las funciones del PROPIO schema (evita tener que enumerar firmas
-- exactas; sigue acotado al dominio del servicio). Incluye registrar_pago_efectivo
-- e increment_offer_usage.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA payment_service_db TO svc_payment;
-- Cruces de lectura + PIN biométrico.
GRANT USAGE ON SCHEMA auth_service_db, access_service_db TO svc_payment;
GRANT SELECT (id, activo, nombre, apellido_paterno, email, pin_terminal, eliminado_en)
  ON auth_service_db.usuarios TO svc_payment;
GRANT EXECUTE ON FUNCTION auth_service_db.assign_pin_terminal(UUID) TO svc_payment;
GRANT SELECT ON access_service_db.historial_accesos TO svc_payment;

CREATE POLICY svc_payment_rw ON payment_service_db.suscripciones            FOR ALL TO svc_payment USING (true) WITH CHECK (true);
CREATE POLICY svc_payment_rw ON payment_service_db.historial_pagos          FOR ALL TO svc_payment USING (true) WITH CHECK (true);
CREATE POLICY svc_payment_rw ON payment_service_db.ofertas                  FOR ALL TO svc_payment USING (true) WITH CHECK (true);
CREATE POLICY svc_payment_rw ON payment_service_db.webhook_events_procesados FOR ALL TO svc_payment USING (true) WITH CHECK (true);
CREATE POLICY svc_payment_ro_u ON auth_service_db.usuarios                  FOR SELECT TO svc_payment USING (true);
CREATE POLICY svc_payment_ro_h ON access_service_db.historial_accesos       FOR SELECT TO svc_payment USING (true);

-- =============================================================================
-- 4) fitness-service → schema fitness_service_db
--    Tablas: catalogo_alimentos, ejercicios(*), progreso_fisico, rutinas, rutina_ejercicios
--    (*) confirmar nombre real: catalogo_ejercicios vs ejercicios
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_fitness') THEN
  CREATE ROLE svc_fitness LOGIN PASSWORD :'FITNESS_DB_PASSWORD' NOBYPASSRLS; END IF; END $$;

GRANT USAGE ON SCHEMA fitness_service_db TO svc_fitness;
GRANT SELECT ON fitness_service_db.catalogo_alimentos TO svc_fitness;                 -- catálogo: solo lectura
GRANT SELECT ON fitness_service_db.ejercicios TO svc_fitness;                          -- catálogo: solo lectura
GRANT SELECT, INSERT, UPDATE, DELETE ON
  fitness_service_db.progreso_fisico,
  fitness_service_db.rutinas,
  fitness_service_db.rutina_ejercicios
  TO svc_fitness;

CREATE POLICY svc_fitness_ro_a ON fitness_service_db.catalogo_alimentos FOR SELECT TO svc_fitness USING (true);
CREATE POLICY svc_fitness_ro_e ON fitness_service_db.ejercicios         FOR SELECT TO svc_fitness USING (true);
CREATE POLICY svc_fitness_rw_p ON fitness_service_db.progreso_fisico    FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
CREATE POLICY svc_fitness_rw_r ON fitness_service_db.rutinas            FOR ALL TO svc_fitness USING (true) WITH CHECK (true);
CREATE POLICY svc_fitness_rw_re ON fitness_service_db.rutina_ejercicios FOR ALL TO svc_fitness USING (true) WITH CHECK (true);

-- =============================================================================
-- 5) ai-service → schema ai_service_db (historial_chat + memoria vectorial)
-- =============================================================================
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_ai') THEN
  CREATE ROLE svc_ai LOGIN PASSWORD :'AI_DB_PASSWORD' NOBYPASSRLS; END IF; END $$;

GRANT USAGE ON SCHEMA ai_service_db TO svc_ai;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai_service_db.historial_chat TO svc_ai;
-- Añadir aquí las tablas de memoria vectorial (pgvector) que use ai-service.

CREATE POLICY svc_ai_rw ON ai_service_db.historial_chat FOR ALL TO svc_ai USING (true) WITH CHECK (true);

-- =============================================================================
-- ROTACIÓN / SALIDA: cuando TODOS los servicios usen su rol nuevo y estén
-- verificados, revocar los privilegios amplios del rol service_role de rutina
-- (mantenerlo solo para operaciones administrativas puntuales) y ROTAR su clave.
-- =============================================================================
