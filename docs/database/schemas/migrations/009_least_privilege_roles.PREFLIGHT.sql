-- =============================================================================
-- 009 · PREFLIGHT (SOLO LECTURA) — verificar el schema REAL antes de ejecutar 009
-- =============================================================================
-- Ejecuta esto PRIMERO en STAGING (Supabase SQL Editor o psql). NO modifica nada.
-- Objetivo: confirmar que los nombres de schema/tabla/función que asume 009
-- existen de verdad, que las tablas tienen RLS activo (deny-all), y que los
-- roles svc_* aún no existen. Si algo no cuadra, se ajusta 009 ANTES de correrla.
-- =============================================================================

-- 1) ¿Existen los 5 schemas esperados?
SELECT 'schema' AS tipo, nspname AS nombre,
       (nspname IN ('auth_service_db','access_service_db','payment_service_db',
                    'fitness_service_db','ai_service_db')) AS esperado
FROM pg_namespace
WHERE nspname LIKE '%_service_db'
ORDER BY nspname;

-- 2) Todas las tablas objetivo: ¿existen y tienen RLS habilitado/forzado?
--    rowsecurity=true  → RLS activo (deny-all debería aplicar a public)
--    Si alguna sale rowsecurity=false, la policy permisiva de 009 no basta:
--    hay que ENABLE ROW LEVEL SECURITY o el GRANT dará acceso directo.
WITH objetivo(schema_name, table_name) AS (
  VALUES
    ('auth_service_db','usuarios'),
    ('auth_service_db','passkey_credentials'),
    ('auth_service_db','tokens_password_reset'),
    ('auth_service_db','refresh_tokens'),
    ('access_service_db','historial_accesos'),
    ('access_service_db','qr_nonces_consumidos'),
    ('access_service_db','tickets_visitas'),
    ('access_service_db','zk_device_commands'),
    ('payment_service_db','suscripciones'),
    ('payment_service_db','historial_pagos'),
    ('payment_service_db','ofertas'),
    ('payment_service_db','webhook_events_procesados'),
    ('fitness_service_db','catalogo_alimentos'),
    ('fitness_service_db','ejercicios'),            -- ⚠ confirmar: ¿ejercicios o catalogo_ejercicios?
    ('fitness_service_db','progreso_fisico'),
    ('fitness_service_db','rutinas'),
    ('fitness_service_db','rutina_ejercicios'),
    ('ai_service_db','historial_chat')
)
SELECT o.schema_name,
       o.table_name,
       (c.relname IS NOT NULL)              AS existe,
       c.relrowsecurity                     AS rls_habilitado,
       c.relforcerowsecurity                AS rls_forzado
FROM objetivo o
LEFT JOIN pg_class c
       ON c.relname = o.table_name
      AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = o.schema_name)
      AND c.relkind = 'r'
ORDER BY o.schema_name, o.table_name;

-- 3) ¿Hay tablas en fitness que se parezcan a "ejercicios"? (resolver el alias)
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'fitness_service_db'
  AND table_name ILIKE '%ejercicio%'
ORDER BY table_name;

-- 4) Tablas de memoria vectorial de ai-service (pgvector) — enumerar para 009.
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'ai_service_db'
ORDER BY table_name;

-- 5) ¿Existen las funciones que 009 concede EXECUTE?
SELECT n.nspname AS schema, p.proname AS funcion,
       pg_get_function_identity_arguments(p.oid) AS firma
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE (n.nspname = 'auth_service_db'    AND p.proname = 'assign_pin_terminal')
   OR (n.nspname = 'payment_service_db' AND p.proname IN ('registrar_pago_efectivo','increment_offer_usage'))
ORDER BY schema, funcion;

-- 6) Políticas deny-all existentes en las tablas objetivo (confirmar el modelo).
--    Se espera ver una policy FOR ALL TO public USING (false) por tabla.
SELECT schemaname, tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname IN ('auth_service_db','access_service_db','payment_service_db',
                     'fitness_service_db','ai_service_db')
ORDER BY schemaname, tablename, policyname;

-- 7) ¿Los roles svc_* ya existen? (deberían NO existir en un staging limpio)
SELECT rolname, rolcanlogin, rolbypassrls
FROM pg_roles
WHERE rolname IN ('svc_auth','svc_access','svc_payment','svc_fitness','svc_ai')
ORDER BY rolname;

-- =============================================================================
-- CRITERIOS PARA CONTINUAR:
--   • Punto 2: todas 'existe=true'. Si 'ejercicios' no existe, usar el nombre
--     que aparezca en el punto 3 y ajustar 009 (tabla + policy svc_fitness_ro_e).
--   • Punto 2: rls_habilitado=true en todas. Si alguna es false, decidir si se
--     habilita RLS o se acepta el GRANT directo (documentarlo).
--   • Punto 4: añadir a 009 las tablas vectoriales de ai que uses.
--   • Punto 5: las 3 funciones existen con su firma (ajustar firma en 009 si difiere).
--   • Punto 7: vacío (roles no existen). Si existen, revisar antes de re-ejecutar.
-- =============================================================================
