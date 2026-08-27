#!/usr/bin/env node
/**
 * @file services/ai-service/scripts/seed-free-exercise-db.js
 * @description ETL de ejercicios: free-exercise-db → Gemini (solo traduce) → Supabase.
 *   Espejo de seed-wger-exercises.js pero desde el dataset de dominio público
 *   free-exercise-db (github.com/yuhonas/free-exercise-db, licencia Unlicense) — el
 *   MISMO que usa openGym. Reemplaza a wger como fuente del catálogo.
 *
 * DIVISIÓN DE RESPONSABILIDADES (principio: la IA enriquece, no inventa)
 *   · Del dataset salen los HECHOS: id, nombre en inglés, equipamiento, músculos
 *     (primarios/secundarios), nivel, categoría y las imágenes (2 frames). El modelo
 *     NUNCA los toca.
 *   · De Gemini sale SOLO: traducción del nombre al español y una descripción breve en
 *     español a partir de las `instructions`. Nada más — nivel y músculos ya vienen
 *     como datos, así que ni se le preguntan.
 *   Ambas partes se FUSIONAN aquí: aunque el modelo alucine no puede corromper ids,
 *   músculos, nivel ni enlaces.
 *
 * ANIMACIONES
 *   Este seed llena `imagen_url` / `thumbnail_url` con los 2 frames estáticos. El GIF
 *   animado (alternando inicio↔fin, estilo openGym) lo genera y sube el script aparte
 *   `rehost-free-exercise-db.js`, que puebla `gif_url`. No se duplica esa lógica aquí.
 *
 * FUENTE
 *   Por defecto descarga el JSON combinado del dataset:
 *     https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
 *   O pásale una copia local con --source ./exercises.json (recomendado para repetir
 *   sin depender de la red).
 *
 * USO
 *   node services/ai-service/scripts/seed-free-exercise-db.js
 *   node services/ai-service/scripts/seed-free-exercise-db.js --source ./exercises.json
 *   node services/ai-service/scripts/seed-free-exercise-db.js --dry-run --limit 40
 *   node services/ai-service/scripts/seed-free-exercise-db.js --replace   (desactiva wger)
 *   node services/ai-service/scripts/seed-free-exercise-db.js --pro       (modelo Pro)
 *
 * VARIABLES
 *   REQUERIDAS: GEMINI_API_KEY, SEED_DATABASE_URL (o SUPABASE_DB_URL / DATABASE_URL)
 *   OPCIONALES: GEMINI_MODEL, GEMINI_MODEL_PRO, SEED_DB_SCHEMA (def: fitness_service_db),
 *               FREE_EXDB_MEDIA_BASE (prefijo de imágenes)
 */

'use strict';

try { require('dotenv').config({ path: `${__dirname}/../.env` }); } catch { /* opcional */ }

// ─── Configuración ───────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const flagVal = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};

const CONFIG = {
  geminiKey: process.env.GEMINI_API_KEY || '',
  geminiModel: flag('pro')
    ? (process.env.GEMINI_MODEL_PRO || 'gemini-3.5-flash')
    : (process.env.GEMINI_MODEL || 'gemini-3.5-flash'),

  table: 'catalogo_ejercicios',
  dbSchema: process.env.SEED_DB_SCHEMA || 'fitness_service_db',
  dbUrl: process.env.SEED_DATABASE_URL || process.env.SUPABASE_DB_URL || process.env.DATABASE_URL || '',

  // Fuente del dataset (JSON combinado) y prefijo de las imágenes relativas.
  sourceFile: flagVal('source', ''),
  sourceUrl: 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json',
  mediaBase: (process.env.FREE_EXDB_MEDIA_BASE
    || 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/').replace(/\/?$/, '/'),

  batchSize: 20,
  dryRun: flag('dry-run'),
  replace: flag('replace'), // desactiva (activo=false) las filas de otras fuentes
  limit: parseInt(flagVal('limit', '0'), 10) || 0,

  maxRetries: 4,
  baseBackoffMs: 800,
};

// ─── Logging ─────────────────────────────────────────────────────────────────
const ts = () => new Date().toISOString().slice(11, 19);
const log = {
  info: (m) => console.log(`[${ts()}] ${m}`),
  ok: (m) => console.log(`[${ts()}] ✅ ${m}`),
  warn: (m) => console.warn(`[${ts()}] ⚠️  ${m}`),
  err: (m) => console.error(`[${ts()}] ❌ ${m}`),
  step: (m) => console.log(`\n[${ts()}] ── ${m} ──`),
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ─── Conexión directa a Postgres (reutiliza el `pg` de fitness-service) ───────
const path = require('path');
let _pgPool = null;
function getPgPool() {
  if (_pgPool) return _pgPool;
  let Pool;
  try {
    ({ Pool } = require('pg'));
  } catch {
    ({ Pool } = require(path.join(__dirname, '../../fitness-service/node_modules/pg')));
  }
  const connectionString = CONFIG.dbUrl.replace(/[?&]sslmode=[^&]+/i, '');
  _pgPool = new Pool({ connectionString, ssl: { rejectUnauthorized: false }, max: 4 });
  return _pgPool;
}
async function closePgPool() {
  if (_pgPool) { try { await _pgPool.end(); } catch { /* noop */ } _pgPool = null; }
}

// ─── fetch con reintentos y backoff exponencial ──────────────────────────────
async function fetchWithRetry(url, options = {}, label = 'petición') {
  let lastErr;
  for (let attempt = 1; attempt <= CONFIG.maxRetries; attempt++) {
    try {
      const res = await fetch(url, options);
      if (res.ok) return res;
      const retriable = res.status === 429 || res.status >= 500;
      if (!retriable) {
        const body = await res.text().catch(() => '');
        throw new Error(`${label} devolvió ${res.status}: ${body.slice(0, 200)}`);
      }
      const retryAfter = Number(res.headers.get('retry-after')) * 1000;
      const backoff = retryAfter || CONFIG.baseBackoffMs * 2 ** (attempt - 1) + Math.random() * 250;
      log.warn(`${label}: HTTP ${res.status}, reintento ${attempt}/${CONFIG.maxRetries} en ${Math.round(backoff)}ms`);
      await sleep(backoff);
    } catch (err) {
      lastErr = err;
      if (attempt === CONFIG.maxRetries) break;
      const backoff = CONFIG.baseBackoffMs * 2 ** (attempt - 1) + Math.random() * 250;
      log.warn(`${label}: ${err.message}. Reintento ${attempt}/${CONFIG.maxRetries} en ${Math.round(backoff)}ms`);
      await sleep(backoff);
    }
  }
  throw new Error(`${label} falló tras ${CONFIG.maxRetries} intentos: ${lastErr?.message || 'desconocido'}`);
}

// ─── Extracción: carga el dataset (local o remoto) y lo trocea en lotes ───────
async function loadDataset() {
  if (CONFIG.sourceFile) {
    const fs = require('fs');
    const abs = path.resolve(CONFIG.sourceFile);
    log.info(`Leyendo dataset local: ${abs}`);
    const raw = fs.readFileSync(abs, 'utf8');
    return JSON.parse(raw);
  }
  log.info(`Descargando dataset: ${CONFIG.sourceUrl}`);
  const res = await fetchWithRetry(CONFIG.sourceUrl, {}, 'free-exercise-db dist');
  return res.json();
}

function* chunk(arr, size) {
  for (let i = 0; i < arr.length; i += size) yield arr.slice(i, i + size);
}

// ─── Mapeo determinista: músculos, nivel, región, media ──────────────────────
/**
 * free-exercise-db usa un vocabulario fijo de músculos en inglés. Lo traducimos a las
 * claves canónicas de src/constants/muscleGroups.js para que los filtros GIN de la app
 * sigan casando. Cada término puede expandirse a 1+ claves canónicas.
 */
const FREE_EXDB_MUSCLE_MAP = {
  abdominals: ['recto_abdominal'],
  abductors: ['gluteo_medio'],
  adductors: ['aductor_mayor'],
  biceps: ['biceps_braquial'],
  calves: ['gemelo_medial', 'soleo'],
  chest: ['pectoral_mayor_esternal'],
  forearms: ['flexores_antebrazo'],
  glutes: ['gluteo_mayor'],
  hamstrings: ['biceps_femoral'],
  lats: ['dorsal_ancho'],
  'lower back': ['erector_espinal'],
  'middle back': ['romboides'],
  neck: ['trapecio_superior'],
  quadriceps: ['cuadriceps_recto'],
  shoulders: ['deltoides_lateral'],
  traps: ['trapecio_superior'],
  triceps: ['triceps_braquial'],
};

// Región de cada clave canónica (subset necesario para derivar region_corporal).
const CANONICAL_REGION = {
  recto_abdominal: 'anterior', gluteo_medio: 'posterior', aductor_mayor: 'anterior',
  biceps_braquial: 'anterior', gemelo_medial: 'posterior', soleo: 'posterior',
  pectoral_mayor_esternal: 'anterior', flexores_antebrazo: 'anterior',
  gluteo_mayor: 'posterior', biceps_femoral: 'posterior', dorsal_ancho: 'posterior',
  erector_espinal: 'posterior', romboides: 'posterior', trapecio_superior: 'posterior',
  cuadriceps_recto: 'anterior', deltoides_lateral: 'anterior', triceps_braquial: 'posterior',
};

const LEVEL_MAP = { beginner: 'principiante', intermediate: 'intermedio', expert: 'avanzado' };

const mapMuscles = (arr) =>
  [...new Set((arr || []).flatMap((m) => FREE_EXDB_MUSCLE_MAP[String(m).toLowerCase()] || []))];

/** Región derivada del primer músculo primario mapeado (enum: anterior|posterior). */
function regionFromMuscles(primaryKeys) {
  for (const k of primaryKeys) if (CANONICAL_REGION[k]) return CANONICAL_REGION[k];
  return 'anterior';
}

/** id entero estable a partir del slug (djb2), para ON CONFLICT(id_wger) idempotente. */
function slugToId(slug) {
  let h = 5381;
  for (let i = 0; i < slug.length; i++) h = ((h << 5) + h + slug.charCodeAt(i)) >>> 0;
  return 100000000 + (h % 1000000000); // 1e8..1.1e9: no choca con ids de wger (1..~1500)
}

/** Datos que NO pasan por el modelo: se toman tal cual del dataset. */
function factsFromExercise(ex) {
  const imgs = Array.isArray(ex.images) ? ex.images : [];
  const toUrl = (rel) => (rel ? (/^https?:\/\//i.test(rel) ? rel : CONFIG.mediaBase + rel) : null);
  const primary = mapMuscles(ex.primaryMuscles);
  const secondary = mapMuscles(ex.secondaryMuscles);
  return {
    slug: String(ex.id || ex.name || '').trim(),
    id_int: slugToId(String(ex.id || ex.name || '').trim()),
    nombre_en: String(ex.name || '').slice(0, 200),
    equipamiento: ex.equipment ? [String(ex.equipment)] : null,
    musculo_principal: primary.length ? primary : null,
    musculo_secundario: secondary.length ? secondary : null,
    region_corporal: regionFromMuscles(primary),
    nivel: LEVEL_MAP[String(ex.level || '').toLowerCase()] || 'intermedio',
    categoria: ex.category ? String(ex.category).slice(0, 80) : null,
    imagen_url: toUrl(imgs[0]),
    thumbnail_url: toUrl(imgs[1] || imgs[0]),
  };
}

/** Reduce a lo mínimo que Gemini necesita ver (solo para traducir). */
function compactForGemini(ex) {
  const instr = Array.isArray(ex.instructions) ? ex.instructions.join(' ') : String(ex.instructions || '');
  return {
    id: String(ex.id || ex.name || '').trim(),
    nombre_en: String(ex.name || ''),
    instrucciones_en: instr.replace(/\s+/g, ' ').trim().slice(0, 900),
  };
}

// ─── Transformación: Gemini (SOLO traduce nombre + descripción) ──────────────
const SYSTEM_PROMPT = `
Eres el motor de ETL del catálogo de ejercicios de GymPro. Recibes un lote de
ejercicios del dataset free-exercise-db (en inglés) y devuelves su versión en ESPAÑOL.

Para cada ejercicio de entrada produce EXACTAMENTE un objeto de salida con el MISMO id.
No añadas ni elimines ejercicios del lote. Tu ÚNICO trabajo es traducir.

Reglas:
- "nombre": traducción natural al español del nombre, capitalización de título.
- "descripcion": reescribe las instrucciones en español claro y conciso (máx 400
  caracteres), sin HTML ni markdown. Si no hay instrucciones útiles, redacta una frase
  breve a partir del nombre.
- NO inventes datos. NO traduzcas el id. NO clasifiques nivel ni músculos (ya son datos).
`.trim();

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ejercicios: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id: { type: 'STRING' },
          nombre: { type: 'STRING' },
          descripcion: { type: 'STRING' },
        },
        required: ['id', 'nombre', 'descripcion'],
      },
    },
  },
  required: ['ejercicios'],
};

async function enrichWithGemini(batch) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${CONFIG.geminiModel}:generateContent?key=${CONFIG.geminiKey}`;
  const userPrompt = `Traduce este lote de ${batch.length} ejercicios:\n${JSON.stringify(batch.map(compactForGemini))}`;

  const res = await fetchWithRetry(
    url,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 8192,
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    },
    'Gemini generateContent',
  );

  const data = await res.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    log.err(`Gemini raw text (primeros 500 chars): ${text.slice(0, 500)}`);
    log.err(`finishReason: ${data.candidates?.[0]?.finishReason}`);
    throw new Error('Gemini devolvió JSON no parseable');
  }
  return parsed.ejercicios || [];
}

// ─── Saneo de texto libre antes de persistir (defensa Stored XSS) ────────────
function sanitizeText(value) {
  if (value == null) return null;
  const cleaned = String(value)
    .replace(/<[^>]*>/g, ' ')
    .replace(/<|>/g, ' ')
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, ' ')
    // eslint-disable-next-line no-control-regex
    .replace(/[\x00-\x1F\x7F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned.length ? cleaned : null;
}

// ─── Fusión: hechos del dataset + traducción de Gemini ───────────────────────
function mergeRows(batch, enriched) {
  const bySlug = new Map(enriched.map((e) => [String(e.id), e]));
  const rows = [];

  for (const ex of batch) {
    const facts = factsFromExercise(ex);
    const ai = bySlug.get(facts.slug);

    if (!ai) {
      log.warn(`Gemini no devolvió "${facts.nombre_en}" (${facts.slug}); se omite`);
      continue;
    }

    rows.push({
      id_wger: facts.id_int,          // id entero estable derivado del slug
      uuid_wger: null,                // free-exercise-db no trae uuid
      nombre: sanitizeText(ai.nombre || facts.nombre_en)?.slice(0, 200) || null,
      nombre_en: sanitizeText(facts.nombre_en)?.slice(0, 200) || null,
      descripcion: sanitizeText(ai.descripcion)?.slice(0, 400) || null,
      categoria: sanitizeText(facts.categoria)?.slice(0, 80) || null,
      nivel: facts.nivel,             // HECHO del dataset (no lo decide el modelo)
      equipamiento: facts.equipamiento,
      musculo_principal: facts.musculo_principal,
      musculo_secundario: facts.musculo_secundario,
      region_corporal: facts.region_corporal,
      imagen_url: facts.imagen_url,
      thumbnail_url: facts.thumbnail_url,
      video_url: null,                // el GIF lo puebla rehost-free-exercise-db.js
      fuente: 'free-exercise-db+gemini',
      idioma_original: 'es',
      activo: true,
    });
  }
  return rows;
}

// ─── Carga: upsert por id_wger ───────────────────────────────────────────────
const UPSERT_COLS = [
  'id_wger', 'uuid_wger', 'nombre', 'nombre_en', 'descripcion', 'categoria', 'nivel',
  'equipamiento', 'musculo_principal', 'musculo_secundario', 'region_corporal',
  'imagen_url', 'thumbnail_url', 'video_url', 'fuente', 'idioma_original', 'activo',
];

async function upsertRows(rows) {
  if (!rows.length) return 0;
  const values = [];
  const tuples = rows.map((r, i) => {
    const base = i * UPSERT_COLS.length;
    const placeholders = UPSERT_COLS.map((_, j) => `$${base + j + 1}`);
    for (const c of UPSERT_COLS) values.push(r[c] ?? null);
    return `(${placeholders.join(', ')})`;
  });
  const updateSet = UPSERT_COLS
    .filter((c) => c !== 'id_wger')
    .map((c) => `"${c}" = EXCLUDED."${c}"`)
    .join(', ');
  const sql = `
    INSERT INTO ${CONFIG.dbSchema}.${CONFIG.table} (${UPSERT_COLS.map((c) => `"${c}"`).join(', ')})
    VALUES ${tuples.join(', ')}
    ON CONFLICT (id_wger) DO UPDATE SET ${updateSet}`;
  await getPgPool().query(sql, values);
  return rows.length;
}

/** Reemplazo suave: desactiva (activo=false) las filas de otras fuentes (p. ej. wger). */
async function deactivateOtherSources() {
  const sql = `
    UPDATE ${CONFIG.dbSchema}.${CONFIG.table}
    SET activo = false
    WHERE fuente IS DISTINCT FROM 'free-exercise-db+gemini' AND activo = true`;
  const res = await getPgPool().query(sql);
  return res.rowCount || 0;
}

// ─── Validación de entorno ───────────────────────────────────────────────────
function checkEnv() {
  const missing = [];
  if (!CONFIG.geminiKey) missing.push('GEMINI_API_KEY');
  if (!CONFIG.dryRun && !CONFIG.dbUrl) {
    missing.push('SEED_DATABASE_URL (connection string de Postgres de Supabase)');
  }
  if (missing.length) {
    log.err(`Faltan variables de entorno: ${missing.join(', ')}`);
    log.info('Cárgalas desde services/ai-service/.env o expórtalas antes de ejecutar.');
    process.exit(1);
  }
}

// ─── Orquestación ────────────────────────────────────────────────────────────
async function main() {
  checkEnv();

  log.step('Seed de ejercicios free-exercise-db → Gemini → Supabase');
  log.info(`Modelo: ${CONFIG.geminiModel} · Tabla: ${CONFIG.table} · ${CONFIG.dryRun ? 'DRY-RUN (no escribe)' : 'ESCRITURA activa'}`);
  if (CONFIG.limit) log.info(`Límite: ${CONFIG.limit} ejercicios`);

  let dataset = await loadDataset();
  if (!Array.isArray(dataset)) {
    // Por si la fuente viene como { exercises: [...] }.
    dataset = dataset.exercises || dataset.results || [];
  }
  if (CONFIG.limit) dataset = dataset.slice(0, CONFIG.limit);
  log.info(`Dataset: ${dataset.length} ejercicios`);

  const stats = { fetched: dataset.length, enriched: 0, upserted: 0, batches: 0, failures: 0 };
  const started = Date.now();

  for (const batch of chunk(dataset, CONFIG.batchSize)) {
    stats.batches++;
    log.info(`Lote ${stats.batches}: ${batch.length} ejercicios`);
    try {
      const enriched = await enrichWithGemini(batch);
      stats.enriched += enriched.length;
      const rows = mergeRows(batch, enriched);

      if (CONFIG.dryRun) {
        log.info(`  [dry-run] ${rows.length} filas listas. Ejemplo: ${rows[0]?.nombre || '—'} · músculos: ${JSON.stringify(rows[0]?.musculo_principal)}`);
      } else {
        const n = await upsertRows(rows);
        stats.upserted += n;
        log.ok(`  ${n} filas upsertadas`);
      }
    } catch (err) {
      stats.failures++;
      log.err(`  Lote ${stats.batches} falló: ${err.message}`);
    }
  }

  if (CONFIG.replace && !CONFIG.dryRun) {
    const n = await deactivateOtherSources();
    log.ok(`Reemplazo: ${n} filas de otras fuentes desactivadas (activo=false)`);
  } else if (CONFIG.replace) {
    log.info('[dry-run] --replace omitido (no escribe)');
  }

  const secs = ((Date.now() - started) / 1000).toFixed(1);
  log.step('Resumen');
  log.info(`Ejercicios dataset: ${stats.fetched}`);
  log.info(`Lotes procesados:   ${stats.batches}`);
  log.info(`Traducidos IA:      ${stats.enriched}`);
  log.info(`Upsertados:         ${CONFIG.dryRun ? '(dry-run)' : stats.upserted}`);
  log.info(`Lotes con error:    ${stats.failures}`);
  log.info(`Tiempo:             ${secs}s`);

  if (stats.failures > 0 && stats.upserted === 0 && !CONFIG.dryRun) {
    log.err('Ningún lote se cargó correctamente.');
    await closePgPool();
    process.exit(1);
  }
  log.ok('Seed completado.');
  await closePgPool();
}

main().catch(async (err) => {
  log.err(`Error fatal: ${err.message}`);
  await closePgPool();
  process.exit(1);
});
