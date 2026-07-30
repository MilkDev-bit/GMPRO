-- =============================================================================
-- 009 · VERIFY — comprobaciones post-ejecución (staging)
-- =============================================================================
-- Corre esto DESPUÉS de 009. Combina inspección de catálogo (roles, policies,
-- privilegios) con pruebas funcionales SET ROLE (positivas y de aislamiento).
-- Ejecutar como superusuario/postgres (Supabase SQL Editor sirve para esto).
-- NO usa ON_ERROR_STOP: las pruebas negativas "esperan" error y lo reportan.
-- =============================================================================

-- 1) Los 5 roles existen, pueden login y NO bypassan RLS (NOBYPASSRLS).
SELECT rolname, rolcanlogin, rolbypassrls,
       (rolcanlogin AND NOT rolbypassrls) AS ok
FROM pg_roles
WHERE rolname IN ('svc_auth','svc_access','svc_payment','svc_fitness')
ORDER BY rolname;
-- Esperado: 4 filas, ok=true en todas. (ai excluido: apátrida)

-- 2) Políticas creadas por rol (una por tabla concedida).
SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE policyname LIKE 'svc\_%'
ORDER BY schemaname, tablename, policyname;
-- Esperado: svc_auth_rw x4; svc_access_rw x4 + svc_access_ro; svc_payment_rw x4
--           + svc_payment_ro_u + svc_payment_ro_h; svc_fitness_* x5.

-- 3) Privilegios de tabla efectivos (muestra representativa).
SELECT 'svc_auth  → usuarios (RW)'        AS caso,
       has_table_privilege('svc_auth','auth_service_db.usuarios','SELECT')  AS sel,
       has_table_privilege('svc_auth','auth_service_db.usuarios','INSERT')  AS ins,
       has_table_privilege('svc_auth','auth_service_db.usuarios','DELETE')  AS del
UNION ALL
SELECT 'svc_access→ usuarios (SELECT col)',
       has_table_privilege('svc_access','auth_service_db.usuarios','SELECT'),
       has_table_privilege('svc_access','auth_service_db.usuarios','INSERT'),
       has_table_privilege('svc_access','auth_service_db.usuarios','DELETE')
UNION ALL
SELECT 'svc_fitness→ ejercicios (RO)',
       has_table_privilege('svc_fitness','fitness_service_db.ejercicios','SELECT'),
       has_table_privilege('svc_fitness','fitness_service_db.ejercicios','INSERT'),
       has_table_privilege('svc_fitness','fitness_service_db.ejercicios','DELETE');
-- Esperado: auth usuarios sel/ins/del = t/t/t; access usuarios = t/f/f;
--           fitness ejercicios = t/f/f (catálogo RO).

-- 4) AISLAMIENTO negativo: un rol NO debe tocar el dominio de otro.
--    (has_schema_privilege sin USAGE → false)
SELECT 'svc_fitness USAGE auth_service_db (debe ser false)' AS caso,
       has_schema_privilege('svc_fitness','auth_service_db','USAGE') AS tiene_usage;
-- Esperado: false.

-- 4b) svc_access SÍ lee las COLUMNAS concedidas de usuarios (grant por columna).
SELECT 'svc_access columnas de usuarios (deben ser true)' AS caso,
       has_column_privilege('svc_access','auth_service_db.usuarios','id','SELECT')     AS col_id,
       has_column_privilege('svc_access','auth_service_db.usuarios','nombre','SELECT') AS col_nombre;
-- Esperado: ambas true. (has_table_privilege da false porque es grant por columna, no de tabla entera.)

-- Supabase: el rol de conexión (postgres) NO es superusuario; para SET ROLE debe ser
-- MIEMBRO de los roles. Se auto-concede la membresía para las pruebas y se revoca al final.
GRANT svc_auth, svc_access, svc_payment, svc_fitness TO current_user;

-- 5) PRUEBA FUNCIONAL positiva: cada rol lee lo SUYO (SET ROLE real + RLS).
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL ROLE svc_fitness;
  SELECT count(*) INTO n FROM fitness_service_db.rutinas;
  RAISE NOTICE 'OK  svc_fitness leyó fitness_service_db.rutinas (% filas)', n;
END $$;

DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL ROLE svc_payment;
  SELECT count(*) INTO n FROM payment_service_db.suscripciones;
  RAISE NOTICE 'OK  svc_payment leyó payment_service_db.suscripciones (% filas)', n;
  -- cruce permitido: lectura de usuarios
  SELECT count(*) INTO n FROM auth_service_db.usuarios;
  RAISE NOTICE 'OK  svc_payment leyó (cruce) auth_service_db.usuarios (% filas)', n;
END $$;

-- 6) PRUEBA FUNCIONAL de AISLAMIENTO: un rol NO puede leer otro dominio.
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL ROLE svc_fitness;
  SELECT count(*) INTO n FROM auth_service_db.usuarios;
  RAISE WARNING '✗ FALLO DE AISLAMIENTO: svc_fitness LEYÓ auth_service_db.usuarios';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'OK  aislamiento: svc_fitness NO puede leer auth (insufficient_privilege)';
END $$;

RESET ROLE;
REVOKE svc_auth, svc_access, svc_payment, svc_fitness FROM current_user;  -- deshacer membresía temporal

-- =============================================================================
-- LECTURA DE RESULTADOS:
--   • Puntos 1–4: valores 'Esperado' cuadran.
--   • Puntos 5–6: en la pestaña de mensajes/NOTICE deben salir solo líneas "OK ";
--     cualquier "✗ FALLO DE AISLAMIENTO" o WARNING = revisar los GRANT/USAGE.
-- =============================================================================
