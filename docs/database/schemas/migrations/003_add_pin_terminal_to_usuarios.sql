-- =============================================================================
-- MIGRACIÓN 003: Agregar pin_terminal a auth_service_db.usuarios
-- =============================================================================
-- Versión      : 003
-- Fecha        : 2026-07-17
-- Autor        : GymPro Engineering
-- Descripción  : Agrega el campo pin_terminal (INTEGER único) a la tabla de
--               usuarios para el mapeo directo con la terminal biométrica
--               ZKTeco SpeedFace-V5L (protocolo ADMS/iClock).
--
--               El PIN de terminal es un número corto (1-9999) asignado por
--               el sistema que identifica al socio en la memoria local de la
--               terminal. Es diferente al UUID de Supabase y al número de socio
--               visible al usuario.
--
-- EJECUCIÓN: Aplicar en Supabase SQL Editor (una sola vez, en orden).
-- =============================================================================

-- 1. Agregar columna pin_terminal (auto-asignable si no se provee)
ALTER TABLE auth_service_db.usuarios
  ADD COLUMN IF NOT EXISTS pin_terminal INTEGER;

-- 2. Índice único para búsquedas rápidas por PIN (O(log n) en lookup de ATTLOG)
CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_pin_terminal
  ON auth_service_db.usuarios (pin_terminal)
  WHERE pin_terminal IS NOT NULL AND eliminado_en IS NULL;

-- 3. Secuencia para auto-asignar PINs únicos (rango 1000-9999 para SpeedFace-V5L)
CREATE SEQUENCE IF NOT EXISTS auth_service_db.pin_terminal_seq
  START WITH 1000
  INCREMENT BY 1
  MINVALUE 1000
  MAXVALUE 9999
  NO CYCLE;

-- 4. Función auxiliar para asignar PIN automáticamente si el usuario no tiene uno
CREATE OR REPLACE FUNCTION auth_service_db.assign_pin_terminal(p_usuario_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_pin INTEGER;
BEGIN
  -- Si ya tiene PIN, retornarlo directamente
  SELECT pin_terminal INTO v_pin
  FROM auth_service_db.usuarios
  WHERE id = p_usuario_id AND eliminado_en IS NULL;

  IF v_pin IS NOT NULL THEN
    RETURN v_pin;
  END IF;

  -- Generar un nuevo PIN único de la secuencia
  v_pin := nextval('auth_service_db.pin_terminal_seq');

  UPDATE auth_service_db.usuarios
  SET pin_terminal = v_pin, actualizado_en = NOW()
  WHERE id = p_usuario_id AND eliminado_en IS NULL;

  RETURN v_pin;
END;
$$;

COMMENT ON COLUMN auth_service_db.usuarios.pin_terminal IS
  'PIN numérico corto (1000-9999) para identificar al socio en la terminal ZKTeco SpeedFace-V5L. Asignado automáticamente al activar membresía.';

-- 5. Verificación
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth_service_db'
      AND table_name   = 'usuarios'
      AND column_name  = 'pin_terminal'
  ) THEN
    RAISE NOTICE '✅ Columna pin_terminal agregada exitosamente a auth_service_db.usuarios';
  ELSE
    RAISE EXCEPTION '❌ Error: pin_terminal no fue creada';
  END IF;
END $$;
