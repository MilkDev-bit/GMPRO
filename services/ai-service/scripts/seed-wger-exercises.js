#!/usr/bin/env node
/**
 * @file services/ai-service/scripts/seed-wger-exercises.js
 * @description ETL de ejercicios: wger API → Gemini (normalización) → Supabase.
 *
 * OBJETIVO
 *   Precargar el catálogo `catalogo_ejercicios` con ejercicios ya
 *   traducidos y normalizados, para que la app NO tenga que llamar a la
 *   IA en cada consulta. Se paga la IA UNA vez aquí; el resultado queda
 *   en la base de datos.
 *
 * DIVISIÓN DE RESPONSABILIDADES (principio: la IA enriquece, no inventa)
 *   · De wger salen los HECHOS: id, nombre en inglés, URLs de imagen y
 *     vídeo, equipamiento. Nunca los toca el modelo.
 *   · De Gemini sale el ENRIQUECIMIENTO: traducción al español, limpieza
 *     de la descripción (sin HTML), clasificación de nivel, normalización
 *     de músculos y región corporal.
 *   Ambas partes se FUSIONAN aquí, así que aunque el modelo alucine no
 *   puede corromper identificadores ni enlaces.
 *
 * NOTAS DE ENTORNO (verificadas contra tu repo)
 *   · Tabla destino: catalogo_ejercicios  (no "exercises")
 *   · Gemini por REST, igual que services/ai-service/src/services/
 *     llmClientService.js  (no se usa el SDK @google/genai)
 *   · Clave: SUPABASE_SERVICE_ROLE_KEY  (con fallback a SUPABASE_SERVICE_KEY)
 *
 * USO
 *   node services/ai-service/scripts/seed-wger-exercises.js
 *   node services/ai-service/scripts/seed-wger-exercises.js --dry-run
 *   node services/ai-service/scripts/seed-wger-exercises.js --limit 40
 *   node services/ai-service/scripts/seed-wger-exercises.js --pro     (usa el modelo Pro)
 *
 * VARIABLES REQUERIDAS
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY
 * OPCIONALES
 *   GEMINI_MODEL (def: gemini-2.0-flash), GEMINI_MODEL_PRO (def: gemini-2.5-pro)
 */

'use strict';

// Carga .env del ai-service si está presente (no falla si no existe).
try { require('dotenv').config({ path: `${__dirname}/../.env` }); } catch { /* opcional */ }

// ─── Configuración ───────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const flagVal = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};

const CONFIG = {
  supabaseUrl: (process.env.SUPABASE_URL || '').replace(/\/$/, ''),
  // Acepta ambos nombres: el nuevo (validado) y el que usa el seed viejo.
  supabaseKey: process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  geminiKey: process.env.GEMINI_API_KEY || '',
  geminiModel: flag('pro')
    ? (process.env.GEMINI_MODEL_PRO || 'gemini-3.5-flash')
    : (process.env.GEMINI_MODEL || 'gemini-3.5-flash'),

  table: 'catalogo_ejercicios',
  // Esquema real de la tabla en Supabase (PostgREST usa Content-Profile para escribir).
  dbSchema: process.env.SUPABASE_DB_SCHEMA || 'fitness_service_db',
  wgerUrl: 'https://wger.de/api/v2/exerciseinfo/?limit=20&language=2',
  batchSize: 20,

  dryRun: flag('dry-run'),
  limit: parseInt(flagVal('limit', '0'), 10) || 0, // 0 = todos

  maxRetries: 4,
  baseBackoffMs: 800,
  wgerDelayMs: 600,   // ~1.6 req/s: por debajo del límite de wger
};

// ─── Logging con marca de tiempo ─────────────────────────────────────────────
const ts = () => new Date().toISOString().slice(11, 19);
const log = {
  info: (m) => console.log(`[${ts()}] ${m}`),
  ok: (m) => console.log(`[${ts()}] ✅ ${m}`),
  warn: (m) => console.warn(`[${ts()}] ⚠️  ${m}`),
  err: (m) => console.error(`[${ts()}] ❌ ${m}`),
  step: (m) => console.log(`\n[${ts()}] ── ${m} ──`),
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ─── fetch con reintentos y backoff exponencial ──────────────────────────────
/**
 * Reintenta ante errores de red y respuestas 429/5xx. Respeta Retry-After.
 * No reintenta ante 4xx (excepto 429): un 400 no se arregla repitiéndolo.
 */
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

      // Backoff: respeta Retry-After si viene; si no, exponencial con jitter.
      const retryAfter = Number(res.headers.get('retry-after')) * 1000;
      const backoff = retryAfter || CONFIG.baseBackoffMs * 2 ** (attempt - 1) + Math.random() * 250;
      log.warn(`${label}: HTTP ${res.status}, reintento ${attempt}/${CONFIG.maxRetries} en ${Math.round(backoff)}ms`);
      await sleep(backoff);
    } catch (err) {
      lastErr = err;
      // Error de red (no una respuesta HTTP): reintentar salvo el último.
      if (attempt === CONFIG.maxRetries) break;
      const backoff = CONFIG.baseBackoffMs * 2 ** (attempt - 1) + Math.random() * 250;
      log.warn(`${label}: ${err.message}. Reintento ${attempt}/${CONFIG.maxRetries} en ${Math.round(backoff)}ms`);
      await sleep(backoff);
    }
  }
  throw new Error(`${label} falló tras ${CONFIG.maxRetries} intentos: ${lastErr?.message || 'desconocido'}`);
}

// ─── Extracción: wger ────────────────────────────────────────────────────────
/**
 * Recorre la paginación de exerciseinfo. Devuelve lotes de CONFIG.batchSize.
 * Como el endpoint ya pagina de 20 en 20, cada página ES un lote.
 */
async function* wgerBatches() {
  let url = CONFIG.wgerUrl;
  let total = 0;

  while (url) {
    const res = await fetchWithRetry(url, {}, 'wger exerciseinfo');
    const data = await res.json();
    const results = data.results || [];

    if (results.length) {
      yield results;
      total += results.length;
    }

    if (CONFIG.limit && total >= CONFIG.limit) return;

    url = data.next; // null cuando no hay más páginas
    if (url) await sleep(CONFIG.wgerDelayMs); // cortesía con el rate limit
  }
}

/** Reduce el objeto de wger a lo mínimo que Gemini necesita ver. */
function compactForGemini(ex) {
  const en = (ex.translations || []).find((t) => t.language === 2) || {};
  return {
    id: ex.id,
    nombre_en: en.name || ex.name || '',
    descripcion_en: (en.description || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 800),
    categoria: ex.category?.name || '',
    equipamiento: (ex.equipment || []).map((e) => e.name),
    musculos: (ex.muscles || []).map((m) => m.name_en || m.name),
    musculos_secundarios: (ex.muscles_secondary || []).map((m) => m.name_en || m.name),
  };
}

/** Datos que NO pasan por el modelo: se toman tal cual de wger. */
function factsFromWger(ex) {
  const img = (ex.images || []).find((i) => i.is_main) || (ex.images || [])[0];
  return {
    id_wger: ex.id,
    uuid_wger: ex.uuid || null,
    nombre_en: ((ex.translations || []).find((t) => t.language === 2)?.name || ex.name || '').slice(0, 200),
    imagen_url: img?.image || null,
    video_url: (ex.videos || [])[0]?.video || null,
    equipamiento_raw: (ex.equipment || []).map((e) => e.name),
  };
}

// ─── Transformación: Gemini (salida estructurada) ────────────────────────────
const SYSTEM_PROMPT = `
Eres el motor de ETL del catálogo de ejercicios de GymPro. Recibes un lote de
ejercicios de la base de datos wger (en inglés) y devuelves su versión
normalizada en ESPAÑOL para nuestra tabla.

Para cada ejercicio de entrada produce EXACTAMENTE un objeto de salida con el
mismo id_wger. No añadas ni elimines ejercicios del lote.

Tu ÚNICO trabajo es traducir y clasificar. Los músculos y la región corporal
se resuelven por otro medio: NO los generes.

Reglas:
- "nombre": traducción natural al español del nombre, capitalización de título.
- "descripcion": reescribe la descripción en español claro y conciso (máx 400
  caracteres), sin HTML, sin markdown. Si la entrada no trae descripción útil,
  redacta una breve de una frase a partir del nombre y los músculos indicados.
- "nivel": clasifica en "principiante", "intermedio" o "avanzado" según la
  complejidad técnica y el riesgo. Ante la duda, "intermedio".
- No inventes datos que no se deriven de la entrada. No traduzcas el id.
`.trim();

/**
 * MAPEOS DETERMINISTAS (copiados de scripts/seed/seed_ejercicios_wger.js).
 *
 * Músculos y región NO los decide Gemini: son HECHOS con vocabulario fijo.
 * - musculo_*: la tabla usa claves canónicas NSCA/ACSM ('pectoral_mayor_
 *   esternal'), y hay un índice GIN por el que la app filtra. Si el modelo
 *   escribiera "pectoral mayor" en texto libre, esos filtros no casarían.
 * - region_corporal: ENUM con SOLO 'anterior' | 'posterior'. Cualquier
 *   otro valor rompe el insert con error de enum.
 */
const WGER_MUSCLE_MAP = {
  1: 'biceps_braquial', 2: 'deltoides_anterior', 3: 'pectoral_mayor_esternal',
  4: 'triceps_braquial', 5: 'dorsal_ancho', 6: 'recto_abdominal',
  7: 'gluteo_mayor', 8: 'cuadriceps_recto', 9: 'biceps_femoral',
  10: 'gemelo_medial', 11: 'trapecio_superior', 12: 'erector_espinal',
  13: 'romboides', 14: 'cuadriceps_vasto_lateral', 15: 'oblicuo_externo',
  16: 'deltoides_lateral', 17: 'braquial', 18: 'braquiorradial',
  19: 'pectoral_mayor_superior', 20: 'pectoral_menor', 21: 'tibial_anterior',
  22: 'soleo',
};

const WGER_CATEGORY_REGION = {
  Chest: 'anterior', Pecho: 'anterior', Back: 'posterior', Espalda: 'posterior',
  Shoulders: 'anterior', Hombros: 'anterior', Arms: 'anterior', Brazos: 'anterior',
  Abs: 'anterior', Abdomen: 'anterior', Legs: 'anterior', Piernas: 'anterior',
  Calves: 'posterior', Pantorrillas: 'posterior', Glutes: 'posterior', 'Glúteos': 'posterior',
};

/**
 * Sanea texto libre ANTES de persistir (defensa contra Stored XSS).
 *
 * Los campos de texto de wger (y la reescritura de Gemini) pueden contener
 * HTML/markup. Aunque `descripcion_en` se despoja de tags antes de mandarla
 * al modelo, lo que se PERSISTE (`nombre`, `nombre_en`, `descripcion`) no
 * pasaba por ningún saneo: un panel web que renderice esos campos como HTML
 * ejecutaría el markup. Se sanea en el sink (justo antes del UPSERT), que es
 * la frontera correcta — no se confía en que el modelo "se porte bien".
 *
 * Estrategia: eliminar tags, neutralizar entidades peligrosas y colapsar
 * espacios. No se usa una librería DOM (dompurify) porque aquí no hay DOM y
 * el objetivo es TEXTO PLANO en la BD, no HTML saneado.
 */
function sanitizeText(value) {
  if (value == null) return null;
  const cleaned = String(value)
    .replace(/<[^>]*>/g, ' ')        // quita cualquier etiqueta
    .replace(/<|>/g, ' ')            // restos de < > sueltos
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, ' ') // entidades HTML
    // eslint-disable-next-line no-control-regex
    .replace(/[\x00-\x1F\x7F]/g, ' ')          // caracteres de control
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned.length ? cleaned : null;
}

const mapMuscles = (arr) =>
  (arr || []).map((m) => WGER_MUSCLE_MAP[m.id] || WGER_MUSCLE_MAP[m]).filter(Boolean);

const regionFromCategory = (categoria) => WGER_CATEGORY_REGION[categoria] || 'anterior';

// Esquema de salida: Gemini no puede desviarse de esta forma.
const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ejercicios: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id_wger: { type: 'INTEGER' },
          nombre: { type: 'STRING' },
          descripcion: { type: 'STRING' },
          nivel: { type: 'STRING', enum: ['principiante', 'intermedio', 'avanzado'] },
          // Músculos y región NO los produce el modelo: se derivan de wger.
        },
        required: ['id_wger', 'nombre', 'descripcion', 'nivel'],
      },
    },
  },
  required: ['ejercicios'],
};

async function enrichWithGemini(batch) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${CONFIG.geminiModel}:generateContent?key=${CONFIG.geminiKey}`;
  const userPrompt = `Normaliza este lote de ${batch.length} ejercicios:\n${JSON.stringify(batch.map(compactForGemini))}`;

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
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
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
    log.err(`Gemini response structure: ${JSON.stringify(Object.keys(data))} candidates: ${data.candidates?.length} finishReason: ${data.candidates?.[0]?.finishReason}`);
    throw new Error('Gemini devolvió JSON no parseable');
  }
  return parsed.ejercicios || [];
}

// ─── Fusión: hechos de wger + enriquecimiento de Gemini ──────────────────────
function mergeRows(batch, enriched) {
  const byId = new Map(enriched.map((e) => [e.id_wger, e]));
  const rows = [];

  for (const ex of batch) {
    const facts = factsFromWger(ex);
    const ai = byId.get(ex.id);

    if (!ai) {
      log.warn(`Gemini no devolvió el ejercicio id=${ex.id} ("${facts.nombre_en}"); se omite`);
      continue;
    }

    rows.push({
      id_wger: facts.id_wger,
      uuid_wger: facts.uuid_wger,
      // Campos de texto SANEADOS antes de persistir (Stored XSS): se limpian
      // en el sink, no se confía en que wger/Gemini no traigan markup.
      nombre: sanitizeText(ai.nombre || facts.nombre_en)?.slice(0, 200) || null,
      nombre_en: sanitizeText(facts.nombre_en)?.slice(0, 200) || null,
      descripcion: sanitizeText(ai.descripcion)?.slice(0, 400) || null,
      categoria: sanitizeText(ex.category?.name)?.slice(0, 80) || null,
      nivel: ['principiante', 'intermedio', 'avanzado'].includes(ai.nivel) ? ai.nivel : 'intermedio',
      // Equipamiento y músculos son HECHOS de wger, no salida del modelo.
      equipamiento: facts.equipamiento_raw.length ? facts.equipamiento_raw : null,
      musculo_principal: mapMuscles(ex.muscles).length ? mapMuscles(ex.muscles) : null,
      musculo_secundario: mapMuscles(ex.muscles_secondary).length ? mapMuscles(ex.muscles_secondary) : null,
      // Derivada de la categoría de wger (enum: solo anterior|posterior).
      region_corporal: regionFromCategory(ex.category?.name),
      imagen_url: facts.imagen_url,
      video_url: facts.video_url,
      fuente: 'wger+gemini',
      idioma_original: 'es',
      activo: true,
    });
  }
  return rows;
}

// ─── Carga: Supabase (upsert vía REST) ───────────────────────────────────────
/**
 * Upsert por id_wger. Requiere una restricción UNIQUE sobre id_wger en la
 * tabla (on_conflict), o Postgres devuelve 42P10.
 */
async function upsertRows(rows) {
  if (!rows.length) return 0;

  const url = `${CONFIG.supabaseUrl}/rest/v1/${CONFIG.table}?on_conflict=id_wger`;
  const res = await fetchWithRetry(
    url,
    {
      method: 'POST',
      headers: {
        apikey: CONFIG.supabaseKey,
        Authorization: `Bearer ${CONFIG.supabaseKey}`,
        'Content-Type': 'application/json',
        // La tabla vive en fitness_service_db (no en public). Sin este header,
        // PostgREST escribiría en el esquema por defecto y daría 404. Requiere que
        // fitness_service_db esté en "Exposed schemas" de Supabase (Settings→API).
        'Content-Profile': CONFIG.dbSchema,
        // merge-duplicates = upsert; return=minimal ahorra ancho de banda.
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify(rows),
    },
    'Supabase upsert',
  );
  // 200/201/204 = ok
  if (res.status >= 200 && res.status < 300) return rows.length;
  return 0;
}

// ─── Validación de entorno ───────────────────────────────────────────────────
function checkEnv() {
  const missing = [];
  if (!CONFIG.supabaseUrl) missing.push('SUPABASE_URL');
  if (!CONFIG.supabaseKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!CONFIG.geminiKey) missing.push('GEMINI_API_KEY');
  if (missing.length) {
    log.err(`Faltan variables de entorno: ${missing.join(', ')}`);
    log.info('Cárgalas desde services/ai-service/.env o expórtalas antes de ejecutar.');
    process.exit(1);
  }
}

// ─── Orquestación ────────────────────────────────────────────────────────────
async function main() {
  checkEnv();

  log.step('Seed de ejercicios wger → Gemini → Supabase');
  log.info(`Modelo: ${CONFIG.geminiModel} · Tabla: ${CONFIG.table} · ${CONFIG.dryRun ? 'DRY-RUN (no escribe)' : 'ESCRITURA activa'}`);
  if (CONFIG.limit) log.info(`Límite: ${CONFIG.limit} ejercicios`);

  const stats = { fetched: 0, enriched: 0, upserted: 0, batches: 0, failures: 0 };
  const started = Date.now();

  for await (const batch of wgerBatches()) {
    stats.batches++;
    const trimmed = CONFIG.limit
      ? batch.slice(0, Math.max(0, CONFIG.limit - stats.fetched))
      : batch;
    stats.fetched += trimmed.length;

    log.info(`Lote ${stats.batches}: ${trimmed.length} ejercicios de wger (acumulado: ${stats.fetched})`);

    try {
      const enriched = await enrichWithGemini(trimmed);
      stats.enriched += enriched.length;

      const rows = mergeRows(trimmed, enriched);

      if (CONFIG.dryRun) {
        log.info(`  [dry-run] ${rows.length} filas listas (no se escriben). Ejemplo: ${rows[0]?.nombre || '—'}`);
      } else {
        const n = await upsertRows(rows);
        stats.upserted += n;
        log.ok(`  ${n} filas upsertadas`);
      }
    } catch (err) {
      stats.failures++;
      // Un lote que falla no aborta el seed entero: se registra y se sigue.
      log.err(`  Lote ${stats.batches} falló: ${err.message}`);
    }

    if (CONFIG.limit && stats.fetched >= CONFIG.limit) break;
  }

  const secs = ((Date.now() - started) / 1000).toFixed(1);
  log.step('Resumen');
  log.info(`Lotes procesados:   ${stats.batches}`);
  log.info(`Ejercicios wger:    ${stats.fetched}`);
  log.info(`Enriquecidos IA:    ${stats.enriched}`);
  log.info(`Upsertados:         ${CONFIG.dryRun ? '(dry-run)' : stats.upserted}`);
  log.info(`Lotes con error:    ${stats.failures}`);
  log.info(`Tiempo:             ${secs}s`);

  if (stats.failures > 0 && stats.upserted === 0 && !CONFIG.dryRun) {
    log.err('Ningún lote se cargó correctamente.');
    process.exit(1);
  }
  log.ok('Seed completado.');
}

main().catch((err) => {
  log.err(`Error fatal: ${err.message}`);
  process.exit(1);
});
