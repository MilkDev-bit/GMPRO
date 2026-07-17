#!/usr/bin/env node
/**
 * @file scripts/seed/seed_ejercicios_wger.js
 * @description Script A — Seeding del catálogo de ejercicios desde wger Workout Manager API
 *
 * FLUJO:
 *   1. Paginación completa sobre GET /api/v2/exercise/?format=json&language=2&limit=100
 *      (language=2 = Inglés; language=4 = Español — intentamos ambos)
 *   2. Para cada ejercicio, obtiene la traducción al español si existe
 *   3. Mapea los IDs de músculos de wger al catálogo canónico NSCA/ACSM
 *   4. Inserta en lotes (BULK INSERT) de 50 registros con ON CONFLICT DO NOTHING
 *
 * RATE LIMITING: Máx. 2 req/s con backoff exponencial en 429/503
 * PROGRESO: Barra de progreso visual en terminal con estadísticas en tiempo real
 *
 * USO:
 *   node scripts/seed/seed_ejercicios_wger.js
 *   node scripts/seed/seed_ejercicios_wger.js --dry-run   (sin insertar en DB)
 *   node scripts/seed/seed_ejercicios_wger.js --lang es   (solo español, default: ambos)
 *
 * VARIABLES DE ENTORNO REQUERIDAS (en .env o entorno):
 *   SUPABASE_URL            — URL del proyecto Supabase
 *   SUPABASE_SERVICE_KEY    — Service Role Key (bypasea RLS)
 */

'use strict';

const https     = require('https');
const http      = require('http');
const readline  = require('readline');
const { URL }   = require('url');

// ─── Configuración ────────────────────────────────────────────────────────────
const CONFIG = {
  supabaseUrl:     process.env.SUPABASE_URL?.replace(/\/$/, '') || '',
  supabaseKey:     process.env.SUPABASE_SERVICE_KEY             || '',
  wgerBaseUrl:     'https://wger.de/api/v2',
  batchSize:       50,        // registros por INSERT bulk
  rateDelayMs:     520,       // ~1.9 req/s → seguro para wger (límite ~2/s)
  maxRetries:      4,
  retryBaseMs:     1000,      // backoff: 1s, 2s, 4s, 8s
  dryRun:          process.argv.includes('--dry-run'),
  // Idiomas wger: 2=Inglés, 4=Español. Probamos español primero, fallback inglés.
  languages:       [4, 2],
};

// ─── Mapeo wger muscle IDs → claves canónicas NSCA/ACSM ─────────────────────
// Fuente: https://wger.de/api/v2/muscle/
// Los IDs de wger son numéricos; se mapean al estándar del proyecto.
const WGER_MUSCLE_MAP = {
  // id_wger: 'clave_canonica'
  1:  'biceps_braquial',
  2:  'deltoides_anterior',
  3:  'pectoral_mayor_esternal',
  4:  'triceps_braquial',
  5:  'dorsal_ancho',
  6:  'recto_abdominal',
  7:  'gluteo_mayor',
  8:  'cuadriceps_recto',
  9:  'biceps_femoral',
  10: 'gemelo_medial',
  11: 'trapecio_superior',
  12: 'erector_espinal',
  13: 'romboides',
  14: 'cuadriceps_vasto_lateral',
  15: 'oblicuo_externo',
  16: 'deltoides_lateral',
  // Músculos adicionales inferidos por categoría wger
  17: 'braquial',
  18: 'braquiorradial',
  19: 'pectoral_mayor_superior',
  20: 'pectoral_menor',
  21: 'tibial_anterior',
  22: 'soleo',
};

// ─── Mapeo categorías wger → región corporal ──────────────────────────────────
const WGER_CATEGORY_REGION = {
  'Chest':           'anterior',
  'Pecho':           'anterior',
  'Back':            'posterior',
  'Espalda':         'posterior',
  'Shoulders':       'anterior',
  'Hombros':         'anterior',
  'Arms':            'anterior',
  'Brazos':          'anterior',
  'Abs':             'anterior',
  'Abdomen':         'anterior',
  'Legs':            'anterior',
  'Piernas':         'anterior',
  'Calves':          'posterior',
  'Pantorrillas':    'posterior',
  'Glutes':          'posterior',
  'Glúteos':         'posterior',
};

// ─── Estado global del seeding ───────────────────────────────────────────────
const stats = {
  total:      0,
  procesados: 0,
  insertados: 0,
  saltados:   0,
  errores:    0,
  startTime:  Date.now(),
};

// ─── Utilidades HTTP ──────────────────────────────────────────────────────────
/**
 * Petición HTTP/HTTPS con reintentos y backoff exponencial.
 * @param {string} urlStr
 * @param {object} options
 * @param {number} [attempt=0]
 * @returns {Promise<object>}
 */
async function fetchJson(urlStr, options = {}, attempt = 0) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(urlStr);
    const lib = parsedUrl.protocol === 'https:' ? https : http;

    const reqOptions = {
      hostname: parsedUrl.hostname,
      path:     parsedUrl.pathname + parsedUrl.search,
      method:   options.method || 'GET',
      headers: {
        'Accept':       'application/json',
        'Content-Type': 'application/json',
        'User-Agent':   'GymPro-Seeder/1.0 (github.com/gympro)',
        ...options.headers,
      },
    };

    const req = lib.request(reqOptions, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        if (res.statusCode === 429 || res.statusCode === 503) {
          // Rate limit hit — backoff exponencial
          if (attempt < CONFIG.maxRetries) {
            const wait = CONFIG.retryBaseMs * Math.pow(2, attempt);
            logLine(`⚠️  Rate limit (${res.statusCode}). Reintentando en ${wait}ms...`);
            setTimeout(() => {
              fetchJson(urlStr, options, attempt + 1).then(resolve).catch(reject);
            }, wait);
          } else {
            reject(new Error(`Rate limit persistente tras ${CONFIG.maxRetries} reintentos en: ${urlStr}`));
          }
          return;
        }
        if (res.statusCode >= 400) {
          reject(new Error(`HTTP ${res.statusCode} en: ${urlStr} — ${body.slice(0, 200)}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error(`JSON inválido desde: ${urlStr}`));
        }
      });
    });

    req.on('error', (err) => {
      if (attempt < CONFIG.maxRetries) {
        const wait = CONFIG.retryBaseMs * Math.pow(2, attempt);
        setTimeout(() => {
          fetchJson(urlStr, options, attempt + 1).then(resolve).catch(reject);
        }, wait);
      } else {
        reject(err);
      }
    });

    if (options.body) {
      req.write(options.body);
    }
    req.end();
  });
}

/**
 * Pausa asíncrona.
 */
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ─── Barra de progreso en terminal ───────────────────────────────────────────
function renderProgress() {
  const pct     = stats.total > 0 ? Math.floor((stats.procesados / stats.total) * 100) : 0;
  const elapsed = ((Date.now() - stats.startTime) / 1000).toFixed(1);
  const rate    = stats.procesados > 0
    ? (stats.procesados / ((Date.now() - stats.startTime) / 1000)).toFixed(1)
    : '0';

  const barWidth = 40;
  const filled   = Math.floor((pct / 100) * barWidth);
  const bar      = '█'.repeat(filled) + '░'.repeat(barWidth - filled);

  const line = [
    `\r  [${bar}] ${pct}%`,
    `  ${stats.procesados}/${stats.total}`,
    `  ✅ ${stats.insertados}`,
    `  ⏭  ${stats.saltados}`,
    `  ❌ ${stats.errores}`,
    `  ${rate} ej/s`,
    `  ${elapsed}s`,
  ].join('  |  ');

  process.stdout.write(line);
}

function logLine(msg) {
  process.stdout.write('\n');
  console.log(msg);
}

// ─── Inserción bulk en Supabase (REST API) ────────────────────────────────────
/**
 * Inserta un lote de ejercicios usando la REST API de Supabase con ON CONFLICT DO NOTHING.
 * @param {object[]} batch
 */
async function insertBatch(batch) {
  if (CONFIG.dryRun || batch.length === 0) {
    stats.insertados += batch.length;
    return;
  }

  const url = `${CONFIG.supabaseUrl}/rest/v1/catalogo_ejercicios`;
  const body = JSON.stringify(batch);

  await fetchJson(url, {
    method: 'POST',
    headers: {
      'apikey':          CONFIG.supabaseKey,
      'Authorization':   `Bearer ${CONFIG.supabaseKey}`,
      'Content-Type':    'application/json',
      'Prefer':          'resolution=ignore-duplicates,return=minimal',
      // 'resolution=ignore-duplicates' = ON CONFLICT DO NOTHING en Supabase REST
    },
    body,
  });

  stats.insertados += batch.length;
}

// ─── Mapeo de ejercicio wger → fila DB ───────────────────────────────────────
/**
 * Transforma un ejercicio de la API wger al formato de la tabla catalogo_ejercicios.
 * @param {object} ejercicioWger
 * @param {object} traduccionEs - Traducción en español (puede ser null)
 * @param {object} categoria
 * @returns {object|null}
 */
function mapearEjercicio(ejercicioWger, traduccionEs, categoria) {
  // Requiere al menos un nombre
  const nombre = traduccionEs?.name || ejercicioWger.name || '';
  if (!nombre || nombre.trim().length < 2) return null;

  // Músculos primarios y secundarios mapeados al estándar NSCA/ACSM
  const musculoPrimario   = (ejercicioWger.muscles || [])
    .map((m) => WGER_MUSCLE_MAP[m.id] || WGER_MUSCLE_MAP[m])
    .filter(Boolean);

  const musculoSecundario = (ejercicioWger.muscles_secondary || [])
    .map((m) => WGER_MUSCLE_MAP[m.id] || WGER_MUSCLE_MAP[m])
    .filter(Boolean);

  // Región corporal basada en categoría
  const categoriaNombre = categoria?.name || '';
  const regionCorporal  = WGER_CATEGORY_REGION[categoriaNombre] || 'anterior';

  // Equipamiento
  const equipamiento = (ejercicioWger.equipment || [])
    .map((e) => (e.name || e).toLowerCase())
    .filter((e) => e !== 'none');

  // UUID de wger (disponible en v2)
  const uuidWger = ejercicioWger.uuid || null;

  // Imagen y video
  const imagenUrl = ejercicioWger.images?.[0]?.image || null;
  const videoUrl  = ejercicioWger.videos?.[0]?.video  || null;

  return {
    id_wger:           ejercicioWger.id,
    uuid_wger:         uuidWger,
    nombre:            nombre.trim().slice(0, 200),
    nombre_en:         ejercicioWger.name?.trim().slice(0, 200) || null,
    descripcion:       (traduccionEs?.description || ejercicioWger.description || '').replace(/<[^>]+>/g, '').trim() || null,
    categoria:         categoriaNombre.slice(0, 80) || null,
    nivel:             'intermedio',
    equipamiento:      equipamiento.length > 0 ? equipamiento : null,
    musculo_principal: musculoPrimario.length > 0 ? musculoPrimario : null,
    musculo_secundario: musculoSecundario.length > 0 ? musculoSecundario : null,
    region_corporal:   regionCorporal,
    imagen_url:        imagenUrl,
    video_url:         videoUrl,
    thumbnail_url:     null,
    fuente:            'wger',
    idioma_original:   traduccionEs ? 'es' : 'en',
    activo:            true,
  };
}

// ─── Obtener traducción al español de un ejercicio ───────────────────────────
/**
 * Busca la traducción en español de un ejercicio dado su ID de wger.
 * endpoint: /api/v2/exercise/?exercise_base=<id>&language=4
 * @param {number} baseId
 * @returns {Promise<object|null>}
 */
async function obtenerTraduccionEs(baseId) {
  try {
    const url = `${CONFIG.wgerBaseUrl}/exercise/?format=json&exercise_base=${baseId}&language=4`;
    const data = await fetchJson(url);
    return data.results?.[0] || null;
  } catch {
    return null;
  }
}

// ─── Seeding principal ───────────────────────────────────────────────────────
async function main() {
  console.log('\n╔══════════════════════════════════════════════════════╗');
  console.log('║  GymPro Seeder — Catálogo de Ejercicios (wger)      ║');
  console.log(`║  Modo: ${CONFIG.dryRun ? 'DRY-RUN (sin insertar)       ' : 'PRODUCCIÓN (inserción real)   '}║`);
  console.log('╚══════════════════════════════════════════════════════╝\n');

  if (!CONFIG.supabaseUrl || !CONFIG.supabaseKey) {
    console.error('❌ SUPABASE_URL y SUPABASE_SERVICE_KEY son requeridas en el entorno.');
    console.error('   Ejemplo: SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_KEY=eyJ...');
    process.exit(1);
  }

  // 1. Obtener catálogo de categorías para enriquecer los registros
  console.log('📋 Cargando catálogo de categorías de wger...');
  let categoriaMap = {};
  try {
    const cats = await fetchJson(`${CONFIG.wgerBaseUrl}/exercisecategory/?format=json&limit=100`);
    for (const cat of (cats.results || [])) {
      categoriaMap[cat.id] = cat;
    }
    console.log(`   ✅ ${Object.keys(categoriaMap).length} categorías cargadas.\n`);
  } catch (err) {
    console.warn(`   ⚠️  No se pudo cargar categorías: ${err.message}. Continuando sin ellas.`);
  }

  // 2. Paginación completa sobre exercise-base (contiene todos los metadatos)
  console.log('🔍 Contando ejercicios disponibles en wger...');
  let nextUrl     = `${CONFIG.wgerBaseUrl}/exerciseinfo/?format=json&limit=100&offset=0`;
  let batch       = [];
  let paginaNum   = 1;

  // Primera petición para obtener el total
  let firstPage;
  try {
    firstPage = await fetchJson(nextUrl);
  } catch (err) {
    console.error(`❌ Error al conectar con wger API: ${err.message}`);
    process.exit(1);
  }

  stats.total = firstPage.count || 0;
  console.log(`   ✅ ${stats.total} ejercicios encontrados en wger.\n`);
  console.log('🚀 Iniciando seeding. Barra de progreso:\n');

  let currentResults = firstPage.results || [];
  nextUrl = firstPage.next;

  while (true) {
    for (const ejercicioInfo of currentResults) {
      stats.procesados++;
      renderProgress();

      try {
        // Buscar traducción al español
        const traduccionEs = await obtenerTraduccionEs(ejercicioInfo.id);
        await sleep(CONFIG.rateDelayMs / 2); // Micro-delay para la sub-petición

        const categoriaId = ejercicioInfo.category?.id;
        const categoria   = categoriaMap[categoriaId] || ejercicioInfo.category || null;

        const fila = mapearEjercicio(ejercicioInfo, traduccionEs, categoria);

        if (!fila) {
          stats.saltados++;
          continue;
        }

        batch.push(fila);

        // Flush del lote cuando alcanza el tamaño configurado
        if (batch.length >= CONFIG.batchSize) {
          await insertBatch(batch);
          batch = [];
        }
      } catch (err) {
        stats.errores++;
        // No abortar: registrar y continuar con el siguiente
      }

      await sleep(CONFIG.rateDelayMs);
    }

    // Siguiente página
    if (!nextUrl) break;

    try {
      const pageData  = await fetchJson(nextUrl);
      currentResults  = pageData.results || [];
      nextUrl         = pageData.next;
      paginaNum++;
    } catch (err) {
      logLine(`⚠️  Error en página ${paginaNum}: ${err.message}. Abortando paginación.`);
      break;
    }

    await sleep(CONFIG.rateDelayMs);
  }

  // Flush del último lote incompleto
  if (batch.length > 0) {
    await insertBatch(batch);
    batch = [];
  }

  // ─── Reporte final ────────────────────────────────────────────────────────
  const elapsed = ((Date.now() - stats.startTime) / 1000).toFixed(1);
  process.stdout.write('\n\n');
  console.log('╔══════════════════════════════════════════════════════╗');
  console.log('║  SEEDING COMPLETADO — Catálogo de Ejercicios         ║');
  console.log('╠══════════════════════════════════════════════════════╣');
  console.log(`║  Total en wger API  : ${String(stats.total).padEnd(29)}║`);
  console.log(`║  Procesados         : ${String(stats.procesados).padEnd(29)}║`);
  console.log(`║  ✅ Insertados       : ${String(stats.insertados).padEnd(29)}║`);
  console.log(`║  ⏭  Saltados (vacíos): ${String(stats.saltados).padEnd(29)}║`);
  console.log(`║  ❌ Errores          : ${String(stats.errores).padEnd(29)}║`);
  console.log(`║  ⏱  Tiempo total     : ${(elapsed + 's').padEnd(29)}║`);
  console.log(`║  Modo               : ${(CONFIG.dryRun ? 'DRY-RUN' : 'PRODUCCIÓN').padEnd(29)}║`);
  console.log('╚══════════════════════════════════════════════════════╝\n');

  process.exit(stats.errores > stats.procesados * 0.2 ? 1 : 0);
}

// ─── Manejo de señales ────────────────────────────────────────────────────────
process.on('SIGINT', () => {
  process.stdout.write('\n\n');
  console.log('⛔ Seeding interrumpido por el usuario.');
  console.log(`   Insertados hasta el momento: ${stats.insertados}`);
  process.exit(0);
});

main().catch((err) => {
  console.error('\n💥 Error fatal en el seeder:', err.message);
  process.exit(1);
});
