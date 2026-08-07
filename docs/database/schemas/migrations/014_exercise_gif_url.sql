-- ═══════════════════════════════════════════════════════════════════════════
-- 014_exercise_gif_url.sql
-- Añade una columna DEDICADA para el GIF/animación de la ejecución correcta del
-- ejercicio, separada de imagen_url (foto estática de wger) y video_url.
--
-- Se puebla EN MASA con scripts/enrich-exercise-media.js (emparejando por nombre
-- contra un dataset externo de GIFs, p. ej. ExerciseDB), sin tocarlos 1 por 1.
--
-- Idempotente: se puede correr varias veces sin error.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE fitness_service_db.catalogo_ejercicios
  ADD COLUMN IF NOT EXISTS gif_url TEXT;

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.gif_url IS
  'GIF/animación de la ejecución correcta del ejercicio (dataset externo, '
  'emparejado por nombre). La app lo prefiere como portada animada.';

-- Índice parcial: acelera "¿cuántos ya tienen animación?" y filtros de cobertura.
CREATE INDEX IF NOT EXISTS ix_ejercicios_con_gif
  ON fitness_service_db.catalogo_ejercicios ((gif_url IS NOT NULL))
  WHERE gif_url IS NOT NULL;
