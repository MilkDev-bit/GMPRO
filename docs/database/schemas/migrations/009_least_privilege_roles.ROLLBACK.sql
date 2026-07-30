-- =============================================================================
-- 009 · ROLLBACK — revertir los roles de mínimo privilegio (staging)
-- =============================================================================
-- Deshace por completo la migración 009: elimina políticas svc_*, revoca los
-- privilegios concedidos y borra los 5 roles. Idempotente y seguro de re-ejecutar.
-- Ejecutar como superusuario/postgres. Ver 009_least_privilege_roles.RUNBOOK.md.
--
-- ⚠ Solo revierte lo que hizo 009. NO toca RLS deny-all ni service_role.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1) Eliminar políticas permisivas svc_* (explícito; IF EXISTS = idempotente).
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.usuarios;
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.passkey_credentials;
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.tokens_password_reset;
DROP POLICY IF EXISTS svc_auth_rw ON auth_service_db.refresh_tokens;

DROP POLICY IF EXISTS svc_access_rw ON access_service_db.historial_accesos;
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.qr_nonces_consumidos;
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.tickets_visitas;
DROP POLICY IF EXISTS svc_access_rw ON access_service_db.zk_device_commands;
DROP POLICY IF EXISTS svc_access_ro ON auth_service_db.usuarios;

DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.suscripciones;
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.historial_pagos;
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.ofertas;
DROP POLICY IF EXISTS svc_payment_rw ON payment_service_db.webhook_events_procesados;
DROP POLICY IF EXISTS svc_payment_ro_u ON auth_service_db.usuarios;
DROP POLICY IF EXISTS svc_payment_ro_h ON access_service_db.historial_accesos;

DROP POLICY IF EXISTS svc_fitness_ro_a ON fitness_service_db.catalogo_alimentos;
DROP POLICY IF EXISTS svc_fitness_ro_e ON fitness_service_db.ejercicios;
DROP POLICY IF EXISTS svc_fitness_rw_p ON fitness_service_db.progreso_fisico;
DROP POLICY IF EXISTS svc_fitness_rw_r ON fitness_service_db.rutinas;
DROP POLICY IF EXISTS svc_fitness_rw_re ON fitness_service_db.rutina_ejercicios;

-- (ai excluido: apátrida, sin schema ni rol)

-- 2) Revocar privilegios restantes (DROP OWNED) y borrar cada rol.
--    DROP OWNED BY limpia GRANTs y cualquier policy residual del rol.
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['svc_auth','svc_access','svc_payment','svc_fitness']
  LOOP
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('DROP OWNED BY %I', r);
      EXECUTE format('DROP ROLE %I', r);
      RAISE NOTICE 'Rol % eliminado', r;
    ELSE
      RAISE NOTICE 'Rol % no existía (nada que hacer)', r;
    END IF;
  END LOOP;
END $$;

COMMIT;

-- Verificación rápida (debe devolver 0 filas):
SELECT rolname FROM pg_roles
WHERE rolname IN ('svc_auth','svc_access','svc_payment','svc_fitness');
