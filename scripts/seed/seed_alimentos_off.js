#!/usr/bin/env node
/**
 * @file scripts/seed/seed_alimentos_off.js
 * @description Script B — Seeding del catálogo nutricional desde Open Food Facts (OFX)
 *
 * ESTRATEGIA DUAL (la más robusta en producción):
 *   Modo A — ARCHIVO LOCAL (recomendado para 5,000+ alimentos):
 *     Descarga el dump CSV/JSONL de OFX filtrado por México y procesa localmente.
 *     Sin límites de rate. Velocidad: ~2,000 alimentos/segundo.
 *     Uso: node seed_alimentos_off.js --file ./en.openfoodfacts.org.products.jsonl
 *
 *   Modo B — API BÚSQUEDA (para pruebas o sets pequeños):
 *     Usa la API de búsqueda de OFX filtrando por países=MX, ordenando por
 *     popularidad (unique_scans_n DESC) para obtener los más comunes.
 *     Límite práctico: ~2,000 registros (la API pública limita profundidad).
 *     Uso: node seed_alimentos_off.js --api
 *
 * SCORE DE COMPLETITUD (0-100):
 *   calorias(20) + proteínas(15) + carbos(15) + grasas(15) + azúcares(10)
 *   + fibra(10) + sodio(10) + imagen(5) = 100 puntos máximo
 *   Solo se insertan registros con score >= 40 (datos nutricionales mínimos útiles)
 *
 * USO:
 *   # Modo API (recomendado para empezar)
 *   node scripts/seed/seed_alimentos_off.js --api
 *
 *   # Modo archivo JSONL (producción — 5,000 registros garantizados)
 *   node scripts/seed/seed_alimentos_off.js --file ./products_mx.jsonl
 *
 *   # Dry-run sin insertar en DB
 *   node scripts/seed/seed_alimentos_off.js --api --dry-run
 *   node scripts/seed/seed_alimentos_off.js --file ./products.jsonl --dry-run
 *
 * VARIABLES DE ENTORNO REQUERIDAS:
 *   SUPABASE_URL            — URL del proyecto Supabase
 *   SUPABASE_SERVICE_KEY    — Service Role Key
 *
 * DESCARGA DEL ARCHIVO JSONL COMPLETO (1.5 GB, filtrado a ~200 MB para MX):
 *   wget -c "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
 *   gunzip openfoodfacts-products.jsonl.gz
 */

'use strict';

const fs        = require('fs');
const readline  = require('readline');
const https     = require('https');
const http      = require('http');
const { URL }   = require('url');

// ─── Configuración ────────────────────────────────────────────────────────────
const CONFIG = {
  supabaseUrl:        process.env.SUPABASE_URL?.replace(/\/$/, '') || '',
  supabaseKey:        process.env.SUPABASE_SERVICE_KEY             || '',
  offApiBase:         'https://world.openfoodfacts.org',
  // Países de interés para GymPro (México + principales de LATAM)
  paisesObjetivo:     ['MX', 'CO', 'AR', 'PE', 'CL', 'VE', 'EC', 'BO', 'PY', 'UY', 'GT', 'HN', 'SV', 'DO'],
  batchSize:          100,       // registros por INSERT bulk (OFX = registros grandes)
  rateDelayMs:        600,       // ~1.6 req/s para la API pública de OFX
  maxRetries:         4,
  retryBaseMs:        1500,
  dryRun:             process.argv.includes('--dry-run'),
  modoApi:            process.argv.includes('--api'),
  modoArchivo:        process.argv.includes('--file'),
  archivoPath:        (() => {
    const idx = process.argv.indexOf('--file');
    return idx !== -1 ? process.argv[idx + 1] : null;
  })(),
  // Número objetivo de alimentos a insertar (modo API)
  objetivoApi:        5000,
  // Score mínimo para considerar un alimento válido (de 100)
  scoreMinimo:        40,
  // Paises con alta prioridad para modo API (búsqueda específica)
  paisPrincipal:      'MX',
};

// ─── Estado global ────────────────────────────────────────────────────────────
const stats = {
  leidos:     0,
  procesados: 0,
  insertados: 0,
  saltados:   0,   // score < mínimo o datos incompletos
  errores:    0,
  startTime:  Date.now(),
};

// ─── Utilidades HTTP ──────────────────────────────────────────────────────────
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
        'User-Agent':   'GymPro-Seeder/1.0 (contacto@gympro.mx)',
        ...options.headers,
      },
    };

    const req = lib.request(reqOptions, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        if (res.statusCode === 429 || res.statusCode === 503) {
          if (attempt < CONFIG.maxRetries) {
            const wait = CONFIG.retryBaseMs * Math.pow(2, attempt);
            logLine(`⚠️  Rate limit OFX (${res.statusCode}). Esperando ${wait}ms...`);
            setTimeout(() => fetchJson(urlStr, options, attempt + 1).then(resolve).catch(reject), wait);
          } else {
            reject(new Error(`Rate limit persistente: ${urlStr}`));
          }
          return;
        }
        if (res.statusCode >= 400) {
          reject(new Error(`HTTP ${res.statusCode} en: ${urlStr}`));
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
        setTimeout(() => fetchJson(urlStr, options, attempt + 1).then(resolve).catch(reject), wait);
      } else {
        reject(err);
      }
    });

    if (options.body) req.write(options.body);
    req.end();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ─── Barra de progreso ────────────────────────────────────────────────────────
function renderProgress(objetivo = 0) {
  const pct     = objetivo > 0 ? Math.min(100, Math.floor((stats.insertados / objetivo) * 100)) : 0;
  const elapsed = ((Date.now() - stats.startTime) / 1000).toFixed(1);
  const rate    = stats.leidos > 0
    ? (stats.leidos / ((Date.now() - stats.startTime) / 1000)).toFixed(0)
    : '0';

  const barWidth = 36;
  const filled   = Math.floor((pct / 100) * barWidth);
  const bar      = '█'.repeat(filled) + '░'.repeat(barWidth - filled);

  const line = [
    `\r  [${bar}] ${String(pct).padStart(3)}%`,
    `  ✅ ${stats.insertados}/${objetivo || '?'}`,
    `  ⏭  ${stats.saltados}`,
    `  ❌ ${stats.errores}`,
    `  ${rate} prod/s`,
    `  ${elapsed}s`,
  ].join('  |  ');

  process.stdout.write(line);
}

function logLine(msg) {
  process.stdout.write('\n');
  console.log(msg);
}

// ─── Cálculo de score de completitud ─────────────────────────────────────────
/**
 * Calcula un score 0-100 basado en la completitud de los datos nutricionales.
 * @param {object} nutriments - Objeto nutriments de OFX
 * @param {string|null} imageUrl
 * @returns {number}
 */
function calcularScore(nutriments, imageUrl) {
  let score = 0;
  const n   = nutriments || {};

  // Calorías (20 pts) — campo más crítico
  if (n['energy-kcal_100g'] != null || n['energy_100g'] != null) score += 20;
  // Proteínas (15 pts)
  if (n['proteins_100g'] != null) score += 15;
  // Carbohidratos (15 pts)
  if (n['carbohydrates_100g'] != null) score += 15;
  // Grasas (15 pts)
  if (n['fat_100g'] != null) score += 15;
  // Azúcares (10 pts)
  if (n['sugars_100g'] != null) score += 10;
  // Fibra (10 pts)
  if (n['fiber_100g'] != null) score += 10;
  // Sodio (10 pts)
  if (n['sodium_100g'] != null || n['salt_100g'] != null) score += 10;
  // Imagen (5 pts)
  if (imageUrl) score += 5;

  return score;
}

// ─── Mapeo producto OFX → fila DB ────────────────────────────────────────────
/**
 * Transforma un producto de Open Food Facts al formato de catalogo_alimentos.
 * @param {object} producto - Objeto completo de OFX
 * @returns {object|null} - null si el producto no cumple los requisitos mínimos
 */
function mapearProducto(producto) {
  // Validaciones básicas de integridad
  const codigoBarras = (producto._id || producto.code || '').toString().trim();
  if (!codigoBarras || codigoBarras.length < 3 || codigoBarras.length > 30) return null;

  const nombre = (
    producto.product_name_es ||     // Español primero
    producto.product_name_es_MX ||  // Español Mexico
    producto.product_name ||        // Fallback genérico
    ''
  ).trim().slice(0, 300);

  if (!nombre || nombre.length < 2) return null;

  // Verificar países
  const paisesProducto = (producto.countries_tags || [])
    .map((p) => p.replace('en:', '').toUpperCase())
    .filter((p) => CONFIG.paisesObjetivo.includes(p));

  // Si el producto no tiene ningún país de interés, saltarlo
  if (paisesProducto.length === 0 && CONFIG.modoApi) return null;

  const nutriments  = producto.nutriments || {};
  const imageUrl    = producto.image_url   || producto.image_front_url || null;
  const scoreCompletitud = calcularScore(nutriments, imageUrl);

  // Filtrar registros con datos nutricionales insuficientes
  if (scoreCompletitud < CONFIG.scoreMinimo) return null;

  // Extraer calorias — OFX usa kcal o kJ, normalizar a kcal
  let calorias = parseFloat(nutriments['energy-kcal_100g']);
  if (isNaN(calorias)) {
    const kj = parseFloat(nutriments['energy_100g']);
    calorias  = isNaN(kj) ? null : parseFloat((kj / 4.184).toFixed(2));
  } else {
    calorias  = parseFloat(calorias.toFixed(2));
  }

  // Validar rango realista de calorías (0-9000 kcal/100g)
  if (calorias !== null && (calorias < 0 || calorias > 9000)) return null;

  // Helper para extraer valor nutricional seguro
  const nutriVal = (key) => {
    const v = parseFloat(nutriments[key]);
    return isNaN(v) || v < 0 ? null : parseFloat(v.toFixed(2));
  };

  // Sodio: OFX almacena en g/100g; convertir a mg/100g
  let sodio = null;
  const sodioG = parseFloat(nutriments['sodium_100g']);
  if (!isNaN(sodioG)) {
    sodio = parseFloat((sodioG * 1000).toFixed(2));
  } else {
    // OFX también almacena 'salt_100g' (sal); sodio ≈ sal × 0.4
    const salG = parseFloat(nutriments['salt_100g']);
    if (!isNaN(salG)) sodio = parseFloat((salG * 400).toFixed(2));
  }

  // Nutriscore y ecoscore
  const nutriscore = (producto.nutriscore_grade || '').toUpperCase();
  const ecoscore   = (producto.ecoscore_grade   || '').toUpperCase();

  // Etiquetas para filtros (vegano, sin gluten, orgánico, etc.)
  const etiquetasRaw = producto.labels_tags || [];
  const etiquetas    = etiquetasRaw
    .map((t) => t.replace('en:', '').replace('es:', '').toLowerCase())
    .filter((t) => t.length > 2 && t.length < 50)
    .slice(0, 20); // Limitar a 20 etiquetas

  // Porciones
  const porcionGramos = parseFloat(producto.serving_size) || null;
  const porciones     = parseFloat(producto.servings_per_container) || null;

  return {
    codigo_barras:          codigoBarras,
    id_off:                 producto._id || codigoBarras,
    nombre:                 nombre,
    nombre_generico:        (producto.generic_name_es || producto.generic_name || '').trim().slice(0, 200) || null,
    marca:                  (producto.brands || '').trim().slice(0, 150) || null,
    categoria:              (producto.categories_tags?.[0] || '').replace(/^[a-z]{2}:/, '').replace(/-/g, ' ').slice(0, 150) || null,
    subcategoria:           (producto.categories_tags?.[1] || '').replace(/^[a-z]{2}:/, '').replace(/-/g, ' ').slice(0, 150) || null,
    ingredientes:           (producto.ingredients_text_es || producto.ingredients_text || '').trim() || null,
    // Valores nutricionales por 100g
    calorias_100g:          calorias,
    proteinas_100g:         nutriVal('proteins_100g'),
    carbohidratos_100g:     nutriVal('carbohydrates_100g'),
    azucares_100g:          nutriVal('sugars_100g'),
    fibra_100g:             nutriVal('fiber_100g'),
    grasas_100g:            nutriVal('fat_100g'),
    grasas_saturadas_100g:  nutriVal('saturated-fat_100g'),
    grasas_trans_100g:      nutriVal('trans-fat_100g'),
    sodio_mg_100g:          sodio,
    calcio_mg_100g:         (() => {
      const v = parseFloat(nutriments['calcium_100g']);
      return isNaN(v) ? null : parseFloat((v * 1000).toFixed(2));
    })(),
    hierro_mg_100g:         (() => {
      const v = parseFloat(nutriments['iron_100g']);
      return isNaN(v) ? null : parseFloat((v * 1000).toFixed(2));
    })(),
    // Porciones
    porcion_gramos:         porcionGramos,
    porciones_envase:       porciones,
    // Metadata
    paises:                 paisesProducto.length > 0 ? paisesProducto : CONFIG.paisesObjetivo,
    idioma_nombre:          'es',
    etiquetas:              etiquetas.length > 0 ? etiquetas : null,
    imagen_url:             imageUrl,
    nutriscore:             ['A','B','C','D','E'].includes(nutriscore) ? nutriscore : null,
    ecoscore:               ['A','B','C','D','E'].includes(ecoscore)  ? ecoscore  : null,
    completitud_score:      scoreCompletitud,
    fuente:                 'open_food_facts',
    activo:                 true,
  };
}

// ─── Inserción bulk en Supabase ───────────────────────────────────────────────
async function insertBatch(batch) {
  if (CONFIG.dryRun || batch.length === 0) {
    stats.insertados += batch.length;
    return;
  }

  const url  = `${CONFIG.supabaseUrl}/rest/v1/catalogo_alimentos`;
  const body = JSON.stringify(batch);

  await fetchJson(url, {
    method: 'POST',
    headers: {
      'apikey':        CONFIG.supabaseKey,
      'Authorization': `Bearer ${CONFIG.supabaseKey}`,
      'Content-Type':  'application/json',
      'Prefer':        'resolution=ignore-duplicates,return=minimal',
    },
    body,
  });

  stats.insertados += batch.length;
}

// ─── MODO A: Seeding desde archivo JSONL ─────────────────────────────────────
async function seedDesdeArchivo(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error(`❌ Archivo no encontrado: ${filePath}`);
    console.error('   Descarga el dump con:');
    console.error('   wget "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"');
    console.error('   gunzip openfoodfacts-products.jsonl.gz');
    process.exit(1);
  }

  const fileStat = fs.statSync(filePath);
  console.log(`📁 Archivo: ${filePath} (${(fileStat.size / 1024 / 1024).toFixed(1)} MB)`);
  console.log(`🎯 Objetivo: ${CONFIG.objetivoApi.toLocaleString()} alimentos con score >= ${CONFIG.scoreMinimo}`);
  console.log('🚀 Procesando línea por línea (streaming). Barra de progreso:\n');

  const rl = readline.createInterface({
    input: fs.createReadStream(filePath, { encoding: 'utf8' }),
    crlfDelay: Infinity,
  });

  let batch = [];

  for await (const line of rl) {
    if (!line.trim()) continue;
    stats.leidos++;

    let producto;
    try {
      producto = JSON.parse(line);
    } catch {
      stats.saltados++;
      continue;
    }

    stats.procesados++;
    const fila = mapearProducto(producto);

    if (!fila) {
      stats.saltados++;
    } else {
      batch.push(fila);

      if (batch.length >= CONFIG.batchSize) {
        try {
          await insertBatch(batch);
        } catch (err) {
          stats.errores += batch.length;
        }
        batch = [];
      }
    }

    renderProgress(CONFIG.objetivoApi);

    // Detener si ya alcanzamos el objetivo
    if (stats.insertados >= CONFIG.objetivoApi) {
      logLine(`✅ Objetivo alcanzado: ${stats.insertados} alimentos insertados.`);
      break;
    }
  }

  // Flush final
  if (batch.length > 0) {
    try {
      await insertBatch(batch);
    } catch (err) {
      stats.errores += batch.length;
    }
  }
}

// ─── MODO B: Seeding desde API de Open Food Facts ────────────────────────────
async function seedDesdeApi() {
  const pageSize = 50; // OFX API: máximo 50 por página (sin auth)
  let page = 1;
  let batch = [];
  let totalObtenidos = 0;

  console.log(`🌐 Modo API — Buscando productos en México (${CONFIG.paisPrincipal})`);
  console.log(`🎯 Objetivo: ${CONFIG.objetivoApi.toLocaleString()} alimentos con score >= ${CONFIG.scoreMinimo}`);
  console.log('📡 Endpoint: world.openfoodfacts.org/cgi/search.pl');
  console.log('🚀 Iniciando paginación:\n');

  // OFX agrupa por país. Probamos primero MX, luego otros países LATAM
  const paisesApis = ['mexico', 'colombia', 'argentina', 'peru', 'chile',
                      'venezuela', 'ecuador', 'guatemala', 'dominican-republic'];

  for (const paisApi of paisesApis) {
    if (stats.insertados >= CONFIG.objetivoApi) break;

    page = 1;
    logLine(`\n🌍 Procesando país: ${paisApi.toUpperCase()}`);

    while (stats.insertados < CONFIG.objetivoApi) {
      const url = new URL(`${CONFIG.offApiBase}/cgi/search.pl`);
      url.searchParams.set('action', 'process');
      url.searchParams.set('tagtype_0', 'countries');
      url.searchParams.set('tag_contains_0', 'contains');
      url.searchParams.set('tag_0', paisApi);
      url.searchParams.set('sort_by', 'unique_scans_n'); // Los más escaneados = más comunes
      url.searchParams.set('page_size', pageSize.toString());
      url.searchParams.set('page', page.toString());
      url.searchParams.set('json', '1');
      url.searchParams.set('fields', [
        '_id', 'code', 'product_name', 'product_name_es', 'product_name_es_MX',
        'generic_name', 'generic_name_es', 'brands', 'categories_tags',
        'labels_tags', 'countries_tags', 'nutriments', 'image_url',
        'image_front_url', 'nutriscore_grade', 'ecoscore_grade',
        'ingredients_text', 'ingredients_text_es', 'serving_size',
        'servings_per_container',
      ].join(','));

      let data;
      try {
        data = await fetchJson(url.toString());
      } catch (err) {
        logLine(`⚠️  Error en página ${page} (${paisApi}): ${err.message}. Continuando...`);
        break;
      }

      const productos = data.products || [];
      if (productos.length === 0) {
        logLine(`   Fin de resultados para ${paisApi} en página ${page}.`);
        break;
      }

      for (const producto of productos) {
        stats.leidos++;
        stats.procesados++;

        const fila = mapearProducto(producto);
        if (!fila) {
          stats.saltados++;
          continue;
        }

        batch.push(fila);

        if (batch.length >= CONFIG.batchSize) {
          try {
            await insertBatch(batch);
          } catch (err) {
            stats.errores += batch.length;
            logLine(`⚠️  Error insertando lote: ${err.message}`);
          }
          batch = [];
        }

        if (stats.insertados >= CONFIG.objetivoApi) break;
      }

      renderProgress(CONFIG.objetivoApi);
      page++;

      await sleep(CONFIG.rateDelayMs);
    }
  }

  // Flush final
  if (batch.length > 0) {
    try {
      await insertBatch(batch);
    } catch (err) {
      stats.errores += batch.length;
    }
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║  GymPro Seeder — Catálogo Nutricional (Open Food Facts)  ║');
  console.log(`║  Modo: ${CONFIG.dryRun ? 'DRY-RUN                              ' : 'PRODUCCIÓN                           '}║`);
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  if (!CONFIG.supabaseUrl || !CONFIG.supabaseKey) {
    console.error('❌ SUPABASE_URL y SUPABASE_SERVICE_KEY son requeridas.');
    process.exit(1);
  }

  if (!CONFIG.modoApi && !CONFIG.modoArchivo) {
    console.error('❌ Especifica el modo de operación:');
    console.error('   --api              → Consume la API pública de Open Food Facts');
    console.error('   --file <ruta.jsonl> → Procesa un archivo JSONL local');
    console.error('\nEjemplo:');
    console.error('   node seed_alimentos_off.js --api');
    console.error('   node seed_alimentos_off.js --file ./products.jsonl');
    process.exit(1);
  }

  // Ejecutar el modo seleccionado
  if (CONFIG.modoArchivo) {
    await seedDesdeArchivo(CONFIG.archivoPath);
  } else {
    await seedDesdeApi();
  }

  // ─── Reporte final ──────────────────────────────────────────────────────
  const elapsed = ((Date.now() - stats.startTime) / 1000).toFixed(1);
  process.stdout.write('\n\n');
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║  SEEDING COMPLETADO — Catálogo Nutricional               ║');
  console.log('╠══════════════════════════════════════════════════════════╣');
  console.log(`║  Líneas leídas       : ${String(stats.leidos).padEnd(32)}║`);
  console.log(`║  Procesados          : ${String(stats.procesados).padEnd(32)}║`);
  console.log(`║  ✅ Insertados        : ${String(stats.insertados).padEnd(32)}║`);
  console.log(`║  ⏭  Saltados (bajo sc): ${String(stats.saltados).padEnd(32)}║`);
  console.log(`║  ❌ Errores de insert : ${String(stats.errores).padEnd(32)}║`);
  console.log(`║  ⏱  Tiempo total      : ${(elapsed + 's').padEnd(32)}║`);
  console.log(`║  Score mínimo        : ${String(CONFIG.scoreMinimo + '/100').padEnd(32)}║`);
  console.log(`║  Modo                : ${(CONFIG.modoArchivo ? 'Archivo JSONL' : 'API OFX').padEnd(32)}║`);
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  if (stats.insertados < 100) {
    console.log('⚠️  Advertencia: Menos de 100 alimentos insertados.');
    console.log('   Si usas --api, considera descargar el dump JSONL para más registros:');
    console.log('   https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz\n');
  }

  process.exit(stats.errores > stats.procesados * 0.3 ? 1 : 0);
}

process.on('SIGINT', () => {
  process.stdout.write('\n\n');
  console.log('⛔ Seeding interrumpido.');
  console.log(`   Insertados: ${stats.insertados}`);
  process.exit(0);
});

main().catch((err) => {
  console.error('\n💥 Error fatal en seeder de alimentos:', err.message);
  process.exit(1);
});
