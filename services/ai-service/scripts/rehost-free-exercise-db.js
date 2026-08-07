/**
 * @file services/ai-service/scripts/rehost-free-exercise-db.js
 * @description Rehospeda en TU backend (Supabase Storage) las animaciones de
 * free-exercise-db. Ese dataset trae 2 JPGs por ejercicio (posición inicial y
 * final); aquí los combinamos en un GIF que alterna inicio↔fin (muestra el
 * movimiento), lo subimos a un bucket público y generamos un media.json
 * [{ name, url }] para poblar `gif_url` con enrich-exercise-media.js.
 *
 * NO hotlinkeamos a GitHub: descargamos, generamos el GIF y lo servimos desde
 * tu propio Storage (control, cache, y respeta el dominio público del dataset).
 *
 * ## Requisitos
 *   - ImageMagick instalado (comando `magick` o `convert`). Es lo que combina
 *     los 2 JPGs en un GIF con resize y loop. (brew install imagemagick /
 *     apt-get install imagemagick)
 *   - Node 18+ (fetch/Blob/Buffer globales).
 *   - Variables:
 *       SUPABASE_URL                 https://<proj>.supabase.co
 *       SUPABASE_SERVICE_ROLE_KEY    service_role (para subir a Storage) — NO se
 *                                    pega en el chat; la exportas tú.
 *
 * ## Uso
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *   node scripts/rehost-free-exercise-db.js --out ./freeexdb-media.json
 *
 *   Luego:
 *   SEED_DATABASE_URL=... \
 *   node scripts/enrich-exercise-media.js --source ./freeexdb-media.json
 *
 *   Flags:
 *     --out <archivo.json>   salida media.json (default: ./freeexdb-media.json)
 *     --bucket <nombre>      bucket de Storage (default: exercise-media)
 *     --limit <n>            procesa sólo los primeros n (para probar)
 *     --width <px>           ancho del GIF (default: 400)
 *     --delay <cs>           centésimas de s por frame (default: 65)
 *     --concurrency <n>      descargas/subidas en paralelo (default: 4)
 *     --skip-existing        no re-sube si el objeto ya existe en el bucket
 *     --dataset-url <url>    override del exercises.json
 */

'use strict';

const fs   = require('fs');
const os   = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

// ─── Flags / config ───────────────────────────────────────────────────────────
function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return (v && !v.startsWith('--')) ? v : true;
}

const CFG = {
  supabaseUrl:  (process.env.SUPABASE_URL || '').replace(/\/$/, ''),
  serviceKey:   process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  out:          arg('out', './freeexdb-media.json'),
  bucket:       arg('bucket', 'exercise-media'),
  limit:        parseInt(arg('limit', '0'), 10) || 0,
  width:        parseInt(arg('width', '400'), 10) || 400,
  delay:        parseInt(arg('delay', '65'), 10) || 65,
  concurrency:  parseInt(arg('concurrency', '4'), 10) || 4,
  skipExisting: arg('skip-existing') === true,
  datasetUrl:   arg('dataset-url', 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json'),
  imageBase:    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/',
};

const ts  = () => new Date().toISOString().slice(11, 19);
const log = {
  info: (m) => console.log(`[${ts()}] ${m}`),
  ok:   (m) => console.log(`[${ts()}] ✅ ${m}`),
  warn: (m) => console.warn(`[${ts()}] ⚠️  ${m}`),
  err:  (m) => console.error(`[${ts()}] ❌ ${m}`),
  step: (m) => console.log(`\n[${ts()}] ── ${m} ──`),
};

// ─── ImageMagick: detección del binario ───────────────────────────────────────
function detectMagick() {
  for (const bin of ['magick', 'convert']) {
    try { execFileSync(bin, ['-version'], { stdio: 'ignore' }); return bin; }
    catch { /* siguiente */ }
  }
  return null;
}

// ─── Descarga con reintentos ──────────────────────────────────────────────────
async function fetchBuffer(url, tries = 3) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return Buffer.from(await res.arrayBuffer());
    } catch (e) { lastErr = e; await new Promise((r) => setTimeout(r, 400 * (i + 1))); }
  }
  throw lastErr;
}

// ─── Supabase Storage (REST) ──────────────────────────────────────────────────
async function ensureBucket() {
  const res = await fetch(`${CFG.supabaseUrl}/storage/v1/bucket`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CFG.serviceKey}`,
      apikey: CFG.serviceKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ name: CFG.bucket, public: true }),
  });
  if (res.ok) { log.ok(`Bucket "${CFG.bucket}" creado (público).`); return; }
  const txt = await res.text().catch(() => '');
  if (res.status === 409 || /already exists/i.test(txt)) { log.info(`Bucket "${CFG.bucket}" ya existe.`); return; }
  throw new Error(`No se pudo crear el bucket (${res.status}): ${txt}`);
}

async function objectExists(objectPath) {
  const res = await fetch(`${CFG.supabaseUrl}/storage/v1/object/info/public/${CFG.bucket}/${objectPath}`, {
    headers: { apikey: CFG.serviceKey, Authorization: `Bearer ${CFG.serviceKey}` },
  });
  return res.ok;
}

async function uploadObject(objectPath, buffer, contentType) {
  const res = await fetch(`${CFG.supabaseUrl}/storage/v1/object/${CFG.bucket}/${objectPath}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CFG.serviceKey}`,
      apikey: CFG.serviceKey,
      'Content-Type': contentType,
      'x-upsert': 'true',
    },
    body: buffer,
  });
  if (!res.ok) throw new Error(`upload ${objectPath} → HTTP ${res.status}: ${await res.text().catch(() => '')}`);
  return `${CFG.supabaseUrl}/storage/v1/object/public/${CFG.bucket}/${objectPath}`;
}

// ─── Procesa un ejercicio: descarga frames → GIF → sube → devuelve {name,url} ──
async function processExercise(ex, magickBin, tmpDir) {
  const imgs = Array.isArray(ex.images) ? ex.images : [];
  if (!imgs.length) return null;
  const objectPath = `${ex.id || ex.name}.gif`.replace(/[^a-zA-Z0-9._/-]/g, '_');

  if (CFG.skipExisting && await objectExists(objectPath)) {
    return { name: ex.name, url: `${CFG.supabaseUrl}/storage/v1/object/public/${CFG.bucket}/${objectPath}`, skipped: true };
  }

  // Descarga hasta 2 frames (inicio/fin). Si sólo hay 1, el GIF será estático.
  const frameFiles = [];
  for (let i = 0; i < Math.min(imgs.length, 2); i++) {
    const buf = await fetchBuffer(CFG.imageBase + imgs[i]);
    const f = path.join(tmpDir, `${objectPath.replace(/\//g, '_')}.${i}.jpg`);
    fs.writeFileSync(f, buf);
    frameFiles.push(f);
  }

  // Combina en GIF con loop infinito. Los frames 0.jpg/1.jpg suelen tener
  // DIMENSIONES DISTINTAS → `-layers optimize` fallaba ("images are not the same
  // size"). Los normalizamos al MISMO lienzo cuadrado (resize + extent) antes de
  // optimizar, así el GIF es válido y consistente.
  const gifFile = path.join(tmpDir, `${objectPath.replace(/\//g, '_')}.gif`);
  const W = CFG.width;
  const args = [
    '-delay', String(CFG.delay), '-loop', '0',
    ...frameFiles,
    '-resize', `${W}x${W}`,
    '-background', 'white', '-gravity', 'center', '-extent', `${W}x${W}`,
    '-layers', 'optimize',
    gifFile,
  ];
  try {
    // Capturamos stderr para mostrar la causa real si ImageMagick falla.
    execFileSync(magickBin, args, { stdio: ['ignore', 'ignore', 'pipe'] });
  } catch (e) {
    const detail = (e.stderr ? e.stderr.toString() : '').trim().split('\n').slice(-1)[0];
    throw new Error(`ImageMagick: ${detail || e.message}`);
  }

  const gifBuf = fs.readFileSync(gifFile);
  const url = await uploadObject(objectPath, gifBuf, 'image/gif');

  // Limpieza de temporales
  for (const f of [...frameFiles, gifFile]) { try { fs.unlinkSync(f); } catch { /* noop */ } }
  return { name: ex.name, url };
}

// ─── Pool de concurrencia simple ──────────────────────────────────────────────
async function runPool(items, worker, size) {
  const results = [];
  let idx = 0, done = 0;
  async function next() {
    const i = idx++;
    if (i >= items.length) return;
    try { const r = await worker(items[i], i); if (r) results.push(r); }
    catch (e) { log.warn(`(${items[i].name}) ${e.message}`); }
    if (++done % 25 === 0) log.info(`Progreso: ${done}/${items.length}`);
    return next();
  }
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, next));
  return results;
}

function checkEnv(magickBin) {
  const miss = [];
  if (!CFG.supabaseUrl) miss.push('SUPABASE_URL');
  if (!CFG.serviceKey) miss.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!magickBin) miss.push('ImageMagick (comando `magick` o `convert`) — instálalo para generar los GIF');
  if (miss.length) { log.err('Faltan requisitos:'); miss.forEach((m) => console.error(`   • ${m}`)); process.exit(1); }
}

async function main() {
  const magickBin = detectMagick();
  checkEnv(magickBin);
  log.step('Rehospedaje de animaciones (free-exercise-db → Supabase Storage)');
  log.info(`ImageMagick: ${magickBin} · bucket: ${CFG.bucket} · ancho: ${CFG.width}px`);

  log.info('Descargando dataset...');
  const dataset = JSON.parse((await fetchBuffer(CFG.datasetUrl)).toString('utf8'));
  let list = dataset.filter((e) => Array.isArray(e.images) && e.images.length);
  if (CFG.limit) list = list.slice(0, CFG.limit);
  log.info(`Ejercicios con imágenes: ${list.length}${CFG.limit ? ` (limitado a ${CFG.limit})` : ''}`);

  await ensureBucket();

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'freeexdb-'));
  log.step('Generando y subiendo GIFs');
  const media = await runPool(list, (ex) => processExercise(ex, magickBin, tmpDir), CFG.concurrency);
  try { fs.rmdirSync(tmpDir); } catch { /* noop */ }

  fs.writeFileSync(CFG.out, JSON.stringify(media.map(({ name, url }) => ({ name, url })), null, 2));
  log.ok(`Subidos ${media.length} GIFs. media.json → ${CFG.out}`);
  log.info('Ahora empareja y puebla gif_url:');
  log.info(`  SEED_DATABASE_URL=... node scripts/enrich-exercise-media.js --source ${CFG.out}`);
}

main().catch((e) => { log.err(e.stack || e.message); process.exit(1); });
