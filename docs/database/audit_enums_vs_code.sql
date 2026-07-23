-- =====================================================================
-- AUDITORÍA: ENUMs de la BD desplegada vs. lo que esperan los validadores
-- de Node.js.  (Parte 1.3 — reconciliación de esquema)
--
-- Ejecutar contra la BD REAL (read-only). No modifica nada.
--   psql "$DATABASE_URL" -f docs/database/audit_enums_vs_code.sql
--   # o: supabase db execute --file docs/database/audit_enums_vs_code.sql
-- =====================================================================

-- 1) Todos los tipos ENUM y sus valores REALES en la BD.
--    Compara esta salida con lo que el código escribe/valida:
--      · suscripciones.estado  → el código usa 'active' | 'past_due' | 'cancelled'
--      · metodo_pago           → el código usa 'cash' | 'card_terminal' | 'transfer'
--    Si la BD devuelve valores en ESPAÑOL ('activa','vencida',…), el
--    código de pagos está escribiendo valores inválidos (falla 22P02) o
--    la columna no es realmente este ENUM.
SELECT n.nspname                                   AS schema,
       t.typname                                   AS enum_type,
       array_agg(e.enumlabel ORDER BY e.enumsortorder) AS valores_reales
FROM pg_type t
JOIN pg_enum e        ON e.enumtypid = t.oid
JOIN pg_namespace n   ON n.oid = t.typnamespace
WHERE n.nspname IN ('public','payment_service_db','access_service_db','auth_service_db')
GROUP BY 1,2
ORDER BY 1,2;

-- 2) Tipo REAL de las columnas de estado/método (¿enum, text, varchar?).
--    Si `data_type` es 'text'/'character varying' en vez de 'USER-DEFINED',
--    el "enum" documentado no aplica y el código en inglés funciona por eso.
SELECT table_schema, table_name, column_name, data_type, udt_name
FROM information_schema.columns
WHERE column_name IN ('estado','metodo_pago','estado_pago','resultado')
  AND table_schema IN ('payment_service_db','access_service_db','public')
ORDER BY table_schema, table_name, column_name;

-- 3) Valores DISTINTOS realmente presentes en la columna estado de
--    suscripciones (la evidencia definitiva de qué idioma usa la BD viva).
--    Si aquí aparece 'active'/'past_due', la BD desplegada ya migró a
--    inglés y el archivo DDL en español está obsoleto.
SELECT estado, COUNT(*) AS filas
FROM payment_service_db.suscripciones
GROUP BY estado
ORDER BY filas DESC;

-- =====================================================================
-- SI la BD viva usa inglés y quieres FORZAR el enum a los valores que el
-- código espera (ejecutar SOLO tras confirmar los pasos 1-3, en
-- ventana de mantenimiento, con backup):
--
--   -- a) Renombrar el enum viejo y crear el correcto
--   ALTER TYPE payment_service_db.estado_suscripcion_enum RENAME TO estado_suscripcion_enum_old;
--   CREATE TYPE payment_service_db.estado_suscripcion_enum AS ENUM
--     ('active','past_due','cancelled','free_pass','suspended');
--   -- b) Migrar la columna (mapear valores viejos→nuevos si los hubiera)
--   ALTER TABLE payment_service_db.suscripciones
--     ALTER COLUMN estado TYPE payment_service_db.estado_suscripcion_enum
--     USING (CASE estado::text
--              WHEN 'activa' THEN 'active' WHEN 'vencida' THEN 'past_due'
--              WHEN 'cancelada' THEN 'cancelled' ELSE estado::text END
--            )::payment_service_db.estado_suscripcion_enum;
--   DROP TYPE payment_service_db.estado_suscripcion_enum_old;
--
-- ⚠ NO ejecutar a ciegas: depende del resultado real de los pasos 1-3.
-- =====================================================================
