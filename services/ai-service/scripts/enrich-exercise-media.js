/**
 * @file services/ai-service/scripts/enrich-exercise-media.js
 * @description Puebla EN MASA la columna de medios (video_url / gif_url) del
 * catálogo de ejercicios emparejando POR NOMBRE contra un dataset externo de
 * GIFs/videos de ejecución — sin tener que hacerlo 1 por 1.
 *
 * ## Por qué
 * wger sólo trae video para un puñado de ejercicios. Para animaciones de la
 * ejecución correcta conviene un dataset con más cobertura y emparejarlo por
 * nombre (usamos `nombre_en`, que casa mejor con datasets en inglés).
 *
 * ## Fuentes recomendadas (descárgalas una vez a un JSON local)
 *   1. ExerciseDB (RapidAPI): ~1300 ejercicios, cada uno con `gifUrl` animado
 *      + target/bodyPart/equipment. Formato: [{ name, gifUrl, target, ... }]
 *   2. free-exercise-db (github.com/yuhonas/free-exercise-db): ~870 ejercicios
 *      con imágenes (2 frames start/end). Formato: [{ name, images:[...], ... }]
 *      Las imágenes son rutas relativas → pásale --media-base con la URL raw.
 *   3. Cualquier JSON propio: [{ name, url }] o [{ name, gifUrl }].
 *
 * El script AUTO-DETECTA el formato y normaliza a { name, url }.
 *
 * ## Uso
 *   SEED_DATABASE_URL="postgres://..." \
 *   node scripts/enrich-exercise-media.js --source ./exercisedb.json
 *
 *   Flags:
 *     --source <archivo.json>   (obligatorio) dataset de medios
 *     --column <video_url|gif_url>  columna destino (default: video_url)
 *     --min-score <0..1>        umbral de similitud de nombre (default: 0.55)
 *     --media-base <url>        prefijo para rutas relativas (free-exercise-db)
 *     --dry-run                 no escribe; sólo reporta cobertura
 *     --report <archivo.json>   guarda los NO emparejados para revisar
 *
 * ## Requisitos
 *   - SEED_DATABASE_URL: cadena de conexión de Postgres (Supabase → Settings →
 *     Database → Connection string). NUNCA se pega en el chat; la exportas tú.
 *   - El catálogo ya poblado (corre antes seed-wger-exercises.js).
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ─── Config / flags ───────────────────────────────────────────────────────────
function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return (v && !v.startsWith('--')) ? v : true; // flag booleano si no hay valor
}

const CONFIG = {
  dbUrl:      process.env.SEED_DATABASE_URL || process.env.SUPABASE_DB_URL || process.env.DATABASE_URL || '',
  dbSchema:   process.env.SEED_DB_SCHEMA || 'fitness_service_db',
  table:      'catalogo_ejercicios',
  source:     arg('source'),
  column:     arg('column', 'gif_url'),
  minScore:   parseFloat(arg('min-score', '0.55')) || 0.55,
  mediaBase:  arg('media-base', ''),
  dryRun:     arg('dry-run') === true,
  report:     arg('report', ''),
};

const ts  = () => new Date().toISOString().slice(11, 19);
const log = {
  info: (m) => console.log(`[${ts()}] ${m}`),
  ok:   (m) => console.log(`[${ts()}] ✅ ${m}`),
  warn: (m) => console.warn(`[${ts()}] ⚠️  ${m}`),
  err:  (m) => console.error(`[${ts()}] ❌ ${m}`),
  step: (m) => console.log(`\n[${ts()}] ── ${m} ──`),
};

// Sólo se permiten columnas de medios conocidas (evita inyección por --column).
const ALLOWED_COLUMNS = new Set(['video_url', 'gif_url', 'imagen_url', 'thumbnail_url']);

// ─── Conexión directa a Postgres (mismo patrón que el seed) ───────────────────
let _pool = null;
function getPool() {
  if (_pool) return _pool;
  let Pool;
  try { ({ Pool } = require('pg')); }
  catch { ({ Pool } = require(path.join(__dirname, '../../fitness-service/node_modules/pg'))); }
  const connectionString = CONFIG.dbUrl.replace(/[?&]sslmode=[^&]+/i, '');
  _pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false }, max: 4 });
  return _pool;
}
async function closePool() { if (_pool) { try { await _pool.end(); } catch { /* noop */ } _pool = null; } }

// ─── Normalización + similitud de nombres ─────────────────────────────────────
const STOP = new Set(['the', 'a', 'an', 'with', 'and', 'of', 'on', 'to', 'for', 'your']);

function normalize(s) {
  return (s || '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '') // quita acentos
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
function tokens(s) {
  return normalize(s).split(' ').filter((t) => t && !STOP.has(t));
}
/** Coeficiente de Dice sobre conjuntos de tokens (0..1). */
function dice(aTokens, bSet) {
  if (!aTokens.length || !bSet.size) return 0;
  let inter = 0;
  const seen = new Set();
  for (const t of aTokens) {
    if (!seen.has(t) && bSet.has(t)) { inter++; seen.add(t); }
  }
  return (2 * inter) / (aTokens.length + bSet.size);
}

// ─── Carga + auto-detección del dataset de medios ─────────────────────────────
function loadDataset(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const arr = Array.isArray(raw) ? raw : (raw.exercises || raw.data || []);
  const out = [];
  for (const it of arr) {
    const name = it.name || it.nombre || it.title;
    if (!name) continue;
    // Auto-detección de la URL del medio según formato de fuente.
    let url =
      it.gifUrl || it.gif || it.video || it.url || it.mediaUrl || null;
    if (!url && Array.isArray(it.images) && it.images.length) {
      // free-exercise-db: rutas relativas → anteponer --media-base.
      url = CONFIG.mediaBase.replace(/\/$/, '') + '/' + String(it.images[0]).replace(/^\//, '');
    }
    if (!url) continue;
    out.push({ name, url, norm: normalize(name), tok: tokens(name) });
  }
  return out;
}

// ─── Emparejamiento catálogo ↔ dataset ────────────────────────────────────────
function buildIndex(dataset) {
  // Índice exacto por nombre normalizado + lista para fuzzy.
  const exact = new Map();
  const list = dataset.map((d) => ({ ...d, set: new Set(d.tok) }));
  for (const d of list) if (!exact.has(d.norm)) exact.set(d.norm, d);
  return { exact, list };
}

function bestMatch(row, index) {
  // Probamos nombre_en y nombre; nos quedamos con el mejor.
  const candidates = [row.nombre_en, row.nombre].filter(Boolean);
  let best = null;
  for (const cand of candidates) {
    const nrm = normalize(cand);
    // 1) exacto
    const ex = index.exact.get(nrm);
    if (ex) return { media: ex, score: 1, via: cand };
    // 2) fuzzy por Dice sobre tokens
    const tks = tokens(cand);
    for (const d of index.list) {
      const score = dice(tks, d.set);
      if (!best || score > best.score) best = { media: d, score, via: cand };
    }
  }
  return best;
}

// ─── Escritura por lotes (UPDATE ... FROM VALUES) ─────────────────────────────
async function applyUpdates(pairs) {
  if (!pairs.length) return 0;
  const pool = getPool();
  const col = CONFIG.column;
  let done = 0;
  const CHUNK = 200;
  for (let i = 0; i < pairs.length; i += CHUNK) {
    const chunk = pairs.slice(i, i + CHUNK);
    const values = [];
    const params = [];
    chunk.forEach((p, j) => {
      values.push(`($${j * 2 + 1}::int, $${j * 2 + 2}::text)`);
      params.push(p.id_wger, p.url);
    });
    const sql = `
      UPDATE ${CONFIG.dbSchema}.${CONFIG.table} AS c
      SET "${col}" = v.url
      FROM (VALUES ${values.join(', ')}) AS v(id_wger, url)
      WHERE c.id_wger = v.id_wger`;
    const res = await pool.query(sql, params);
    done += res.rowCount || 0;
  }
  return done;
}

async function ensureColumn() {
  // Si la columna destino no es de wger estándar (p.ej. gif_url), la creamos.
  if (['imagen_url', 'thumbnail_url', 'video_url'].includes(CONFIG.column)) return;
  const pool = getPool();
  await pool.query(
    `ALTER TABLE ${CONFIG.dbSchema}.${CONFIG.table} ADD COLUMN IF NOT EXISTS "${CONFIG.column}" TEXT`,
  );
  log.info(`Columna "${CONFIG.column}" asegurada (ADD COLUMN IF NOT EXISTS).`);
}

function checkEnv() {
  const missing = [];
  if (!CONFIG.source) missing.push('--source <archivo.json> (dataset de GIFs/videos)');
  if (!CONFIG.dryRun && !CONFIG.dbUrl) missing.push('SEED_DATABASE_URL (cadena de conexión Postgres)');
  if (!ALLOWED_COLUMNS.has(CONFIG.column)) missing.push(`--column inválida (permitidas: ${[...ALLOWED_COLUMNS].join(', ')})`);
  if (CONFIG.source && !fs.existsSync(CONFIG.source)) missing.push(`el archivo --source no existe: ${CONFIG.source}`);
  if (missing.length) {
    log.err('Faltan requisitos:');
    for (const m of missing) console.error(`   • ${m}`);
    process.exit(1);
  }
}

async function main() {
  checkEnv();
  log.step('Enriquecimiento de medios de ejercicios');
  log.info(`Fuente: ${CONFIG.source} · columna destino: ${CONFIG.column} · umbral: ${CONFIG.minScore}${CONFIG.dryRun ? ' · DRY-RUN' : ''}`);

  const dataset = loadDataset(CONFIG.source);
  log.info(`Dataset cargado: ${dataset.length} medios con URL.`);
  if (!dataset.length) { log.err('El dataset no tiene entradas con URL de medio.'); process.exit(1); }
  const index = buildIndex(dataset);

  const pool = getPool();
  const { rows } = await pool.query(
    `SELECT id_wger, nombre, nombre_en FROM ${CONFIG.dbSchema}.${CONFIG.table} ORDER BY id_wger`,
  );
  log.info(`Catálogo: ${rows.length} ejercicios.`);

  const updates = [];
  const unmatched = [];
  for (const row of rows) {
    const m = bestMatch(row, index);
    if (m && m.score >= CONFIG.minScore) {
      updates.push({ id_wger: row.id_wger, url: m.media.url, score: +m.score.toFixed(2), name: row.nombre_en || row.nombre, match: m.media.name });
    } else {
      unmatched.push({ id_wger: row.id_wger, nombre: row.nombre_en || row.nombre, bestScore: m ? +m.score.toFixed(2) : 0, bestGuess: m?.media?.name || null });
    }
  }

  log.step('Resultado del emparejamiento');
  log.ok(`Emparejados: ${updates.length}/${rows.length} (${((updates.length / rows.length) * 100).toFixed(1)}%)`);
  log.warn(`Sin emparejar: ${unmatched.length}`);
  // Muestra unas cuantas coincidencias para que valides la calidad.
  for (const u of updates.slice(0, 8)) log.info(`  ✓ ${u.name}  →  ${u.match}  (${u.score})`);

  if (CONFIG.report) {
    fs.writeFileSync(CONFIG.report, JSON.stringify(unmatched, null, 2));
    log.info(`No emparejados escritos en ${CONFIG.report} (revísalos y baja --min-score si hace falta).`);
  }

  if (CONFIG.dryRun) { log.info('DRY-RUN: no se escribió nada.'); await closePool(); return; }

  await ensureColumn();
  log.step('Escribiendo en la base de datos');
  const written = await applyUpdates(updates);
  log.ok(`Filas actualizadas: ${written}.`);
  await closePool();
}

main().catch(async (e) => { log.err(e.stack || e.message); await closePool(); process.exit(1); });
