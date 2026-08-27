# Runbook — Sembrar el catálogo desde free-exercise-db

Guía paso a paso para poblar `catalogo_ejercicios` con el dataset de dominio público
**free-exercise-db** (el mismo que usa openGym) y reemplazar wger. Cubre catálogo +
animaciones (GIF) + verificación + rollback.

> Todo corre desde la raíz del monorepo salvo que se indique. Node **≥ 22** (lo exige
> `services/ai-service/package.json`).

---

## 0) Qué vas a ejecutar (visión general)

1. **Preparar** — instalar `pg` y reunir 2 secretos (DB + Gemini).
2. **Catálogo** — `seed-free-exercise-db.js` (traduce con Gemini, escribe filas).
3. **Reemplazo** — el mismo comando con `--replace` desactiva las filas de wger.
4. **Animaciones** — `rehost-free-exercise-db.js` + `enrich-exercise-media.js` pueblan `gif_url`.
5. **Verificar** — 4 consultas SQL.
6. **Rollback** — cómo revertir (es reversible).

---

## 1) Prerrequisitos

### 1.1 Instalar la dependencia `pg`
El script escribe por conexión directa de Postgres. Hoy **no** está instalada:

```bash
cd services/ai-service
npm install pg
cd ../..
```

### 1.2 Reunir los 2 secretos

| Variable | Dónde sacarla |
|---|---|
| `SEED_DATABASE_URL` | Supabase → **Settings → Database → Connection string → URI** (usa el puerto del **pooler**, 6543, o el directo 5432). Empieza por `postgres://postgres:...` |
| `GEMINI_API_KEY` | Google AI Studio → API key (la misma que ya usa `ai-service`) |

Expórtalas en tu terminal (no las pegues en el chat ni las commitees):

```bash
export SEED_DATABASE_URL="postgres://postgres:TU_PASS@aws-0-xxxx.pooler.supabase.com:6543/postgres"
export GEMINI_API_KEY="AIza...."
```

> Opcionales: `GEMINI_MODEL` (def. `gemini-3.5-flash`), `SEED_DB_SCHEMA`
> (def. `fitness_service_db`), `FREE_EXDB_MEDIA_BASE` (prefijo de imágenes).

### 1.3 (Recomendado) Descargar el dataset una vez
Así el seed no depende de la red y puedes repetirlo:

```bash
curl -L -o /tmp/free-exercise-db.json \
  https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
```

(Si no lo descargas, el script lo baja solo.)

### 1.4 Confirmar la restricción UNIQUE (una vez)
El upsert usa `ON CONFLICT (id_wger)`. La tabla ya la tenía para el seed de wger, pero
verifícalo:

```sql
-- En el SQL editor de Supabase
SELECT conname FROM pg_constraint
WHERE conrelid = 'fitness_service_db.catalogo_ejercicios'::regclass
  AND contype IN ('p','u');
-- Debe listar una PK o UNIQUE que incluya id_wger. Si no existe:
-- ALTER TABLE fitness_service_db.catalogo_ejercicios
--   ADD CONSTRAINT catalogo_ejercicios_id_wger_key UNIQUE (id_wger);
```

---

## 2) Catálogo — prueba en seco (no escribe)

Siempre primero. Valida credenciales, formato y el mapeo de músculos sin tocar la BD:

```bash
node services/ai-service/scripts/seed-free-exercise-db.js \
  --source /tmp/free-exercise-db.json --dry-run --limit 40
```

Qué mirar en el log:
- `Dataset: N ejercicios`
- Por lote: `[dry-run] X filas listas. Ejemplo: <nombre> · músculos: ["..."]`
- Si vieras `musculo_principal: null` en algún ejemplo → ese ejercicio venía sin músculo
  en el origen (raro; se inserta igual con `null`).

---

## 3) Catálogo — carga real

Sin `--limit` para todo el dataset (~800). Escribe/actualiza por `id_wger` (idempotente:
puedes re-correrlo sin duplicar):

```bash
node services/ai-service/scripts/seed-free-exercise-db.js \
  --source /tmp/free-exercise-db.json
```

Al final verás el resumen: `Upsertados: N`, `Lotes con error: 0`.

> Coste: es 1 llamada a Gemini por lote de 20 (~40 llamadas para 800). Se paga **una
> vez**; el resultado queda en la BD.

---

## 4) Reemplazar wger (desactivar sus filas)

Cuando estés conforme con el catálogo nuevo, desactiva (soft, reversible) las filas de
otras fuentes:

```bash
node services/ai-service/scripts/seed-free-exercise-db.js \
  --source /tmp/free-exercise-db.json --replace
```

`--replace` hace `UPDATE ... SET activo=false WHERE fuente <> 'free-exercise-db'`.
**No borra nada** — wger queda inactivo y recuperable.

---

## 5) Animaciones (GIF estilo openGym)

Los 2 frames estáticos ya quedaron en `imagen_url`/`thumbnail_url`. Para el GIF animado:

### 5.1 Requisito: ImageMagick
```bash
# macOS:  brew install imagemagick
# Ubuntu: sudo apt-get install imagemagick
magick -version   # o: convert -version
```

### 5.2 Generar + rehospedar los GIF en tu Storage
Necesita el service role (solo para subir a Storage):

```bash
export SUPABASE_URL="https://TU_PROYECTO.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="eyJ...service_role..."

node services/ai-service/scripts/rehost-free-exercise-db.js --out /tmp/freeexdb-media.json
```

Produce `/tmp/freeexdb-media.json` con `[{ name, url }]` (GIFs ya subidos a tu bucket).

### 5.3 Poblar `gif_url` emparejando por nombre
El emparejamiento casa casi perfecto porque el catálogo y los GIF vienen del **mismo
dataset** (mismos `name`):

```bash
node services/ai-service/scripts/enrich-exercise-media.js \
  --source /tmp/freeexdb-media.json --column gif_url --min-score 0.6
```

---

## 6) Verificación (SQL en Supabase)

```sql
-- 6.1 Cuántos activos por fuente
SELECT fuente, count(*) FILTER (WHERE activo) AS activos, count(*) AS total
FROM fitness_service_db.catalogo_ejercicios
GROUP BY fuente ORDER BY total DESC;

-- 6.2 ¿Alguno sin músculo principal? (debería ser 0 o casi)
SELECT count(*) AS sin_musculo
FROM fitness_service_db.catalogo_ejercicios
WHERE fuente = 'free-exercise-db'
  AND (musculo_principal IS NULL OR cardinality(musculo_principal) = 0);

-- 6.3 Cobertura de animación (gif_url)
SELECT
  count(*) AS total,
  count(gif_url) AS con_gif,
  round(100.0 * count(gif_url) / nullif(count(*),0), 1) AS pct_gif
FROM fitness_service_db.catalogo_ejercicios
WHERE fuente = 'free-exercise-db' AND activo;

-- 6.4 Muestra: nombre traducido + músculos + imagen
SELECT nombre, nombre_en, nivel, musculo_principal, imagen_url IS NOT NULL AS tiene_img
FROM fitness_service_db.catalogo_ejercicios
WHERE fuente = 'free-exercise-db' ORDER BY random() LIMIT 10;
```

---

## 7) Rollback

Todo es reversible sin pérdida de datos:

```sql
-- Reactivar wger y desactivar free-exercise-db (volver al estado anterior)
UPDATE fitness_service_db.catalogo_ejercicios SET activo = true  WHERE fuente = 'wger+gemini';
UPDATE fitness_service_db.catalogo_ejercicios SET activo = false WHERE fuente = 'free-exercise-db';

-- O borrar por completo lo sembrado (si prefieres empezar de cero)
-- DELETE FROM fitness_service_db.catalogo_ejercicios WHERE fuente = 'free-exercise-db';
```

---

## 8) Problemas comunes

| Síntoma | Causa / arreglo |
|---|---|
| `Cannot find module 'pg'` | Falta el paso 1.1 → `cd services/ai-service && npm install pg` |
| `Faltan variables de entorno: SEED_DATABASE_URL` | No exportaste la URL (paso 1.2) |
| `... devolvió 42P10` (no unique) | Falta la UNIQUE en `id_wger` (paso 1.4) |
| `self-signed certificate` | El script ya quita `sslmode` y fuerza `rejectUnauthorized:false`; usa la URI del pooler |
| Gemini `MAX_TOKENS`/JSON truncado | Baja el lote (edita `batchSize`) o usa `--pro` |
| `magick: command not found` | Instala ImageMagick (paso 5.1) |
| GIF mal emparejado | Sube `--min-score` (0.7–0.8) en el paso 5.3 |

---

## Resumen ejecutable (copia-pega)

```bash
# Prep
cd services/ai-service && npm install pg && cd ../..
export SEED_DATABASE_URL="postgres://..."   GEMINI_API_KEY="AIza..."
curl -L -o /tmp/fx.json https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json

# Catálogo (dry-run → real → replace)
node services/ai-service/scripts/seed-free-exercise-db.js --source /tmp/fx.json --dry-run --limit 40
node services/ai-service/scripts/seed-free-exercise-db.js --source /tmp/fx.json
node services/ai-service/scripts/seed-free-exercise-db.js --source /tmp/fx.json --replace

# Animaciones
export SUPABASE_URL="https://...supabase.co" SUPABASE_SERVICE_ROLE_KEY="eyJ..."
node services/ai-service/scripts/rehost-free-exercise-db.js --out /tmp/fx-media.json
node services/ai-service/scripts/enrich-exercise-media.js --source /tmp/fx-media.json --column gif_url --min-score 0.6
```
