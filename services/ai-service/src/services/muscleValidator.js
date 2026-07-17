/**
 * @file services/ai-service/src/services/muscleValidator.js
 * @description Validador y AUTO-CORRECTOR de claves musculares generadas por la IA
 * (Eje 1 de la auditoría). Sustituye al filtro "borra en silencio" del
 * recommendationController por una estrategia de corrección robusta:
 *
 *   1. Normaliza (minúsculas, sin acentos, guiones/espacios → '_').
 *   2. Match exacto contra VALID_MUSCLE_KEYS.
 *   3. Match por etiqueta legible (label) y sinónimos comunes.
 *   4. Fuzzy-match por distancia de Levenshtein (umbral configurable) para
 *      recuperar claves con typos ("triceps_braqual" → "triceps_braquial").
 *   5. Si tras todo sigue sin resolver, se descarta y se registra.
 *
 * Además garantiza los INVARIANTES del plan antes de responder:
 *   • Cada ejercicio tiene ≥1 músculo primario (si queda vacío, hereda del
 *     enfoque_muscular del día o se marca para descarte controlado).
 *   • ejercicio_id con formato válido.
 */

'use strict';

const { VALID_MUSCLE_KEYS, MUSCLE_CATALOG } = require('../constants/muscleGroups');

// ── Índices precomputados (una sola vez al cargar el módulo) ──────────────────
function normalize(str) {
  return String(str)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // quitar acentos (diacríticos combinantes)
    .toLowerCase()
    .trim()
    .replace(/[\s\-]+/g, '_')
    .replace(/[^a-z0-9_]/g, '');
}

// Sinónimos frecuentes que la IA suele emitir → clave canónica.
const SYNONYMS = {
  pectoral:           'pectoral_mayor_esternal',
  pecho:              'pectoral_mayor_esternal',
  pectoral_mayor:     'pectoral_mayor_esternal',
  triceps:            'triceps_braquial',
  biceps:             'biceps_braquial',
  dorsales:           'dorsal_ancho',
  dorsal:             'dorsal_ancho',
  espalda_alta:       'trapecio_medio',
  lumbares:           'erector_espinal',
  abdominales:        'recto_abdominal',
  abdomen:            'recto_abdominal',
  core:               'recto_abdominal',
  gluteos:            'gluteo_mayor',
  gluteo:             'gluteo_mayor',
  cuadriceps:         'cuadriceps_recto',
  femoral:            'biceps_femoral',
  isquiotibiales:     'biceps_femoral',
  isquios:            'biceps_femoral',
  gemelos:            'gemelo_medial',
  pantorrilla:        'gemelo_medial',
  deltoides:          'deltoides_lateral',
  hombro:             'deltoides_lateral',
  antebrazo:          'flexores_antebrazo',
};

// Índice normalizado clave-exacta y por etiqueta.
const NORMALIZED_KEY_INDEX = new Map();
for (const key of VALID_MUSCLE_KEYS) {
  NORMALIZED_KEY_INDEX.set(normalize(key), key);
  const label = MUSCLE_CATALOG[key]?.label;
  if (label) NORMALIZED_KEY_INDEX.set(normalize(label), key);
}
for (const [syn, key] of Object.entries(SYNONYMS)) {
  if (!NORMALIZED_KEY_INDEX.has(normalize(syn))) {
    NORMALIZED_KEY_INDEX.set(normalize(syn), key);
  }
}

/** Distancia de Levenshtein (iterativa, O(n·m)). */
function levenshtein(a, b) {
  const m = a.length, n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  let prev = Array.from({ length: n + 1 }, (_, i) => i);
  let curr = new Array(n + 1);
  for (let i = 1; i <= m; i++) {
    curr[0] = i;
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, curr] = [curr, prev];
  }
  return prev[n];
}

/**
 * Resuelve una clave muscular arbitraria a una clave canónica válida.
 *
 * @param {string} raw
 * @param {number} [maxDistance=2] - Umbral de Levenshtein para fuzzy-match.
 * @returns {{ key: string|null, method: 'exact'|'label_or_synonym'|'fuzzy'|'unresolved' }}
 */
function correctMuscleKey(raw, maxDistance = 2) {
  if (!raw || typeof raw !== 'string') return { key: null, method: 'unresolved' };
  const norm = normalize(raw);

  // 1-3. Exacto / etiqueta / sinónimo
  const direct = NORMALIZED_KEY_INDEX.get(norm);
  if (direct) {
    return { key: direct, method: VALID_MUSCLE_KEYS.includes(direct) && normalize(direct) === norm ? 'exact' : 'label_or_synonym' };
  }

  // 4. Fuzzy contra las claves canónicas normalizadas
  let best = null, bestDist = Infinity;
  for (const key of VALID_MUSCLE_KEYS) {
    const d = levenshtein(norm, normalize(key));
    if (d < bestDist) { bestDist = d; best = key; }
  }
  if (best && bestDist <= maxDistance) {
    return { key: best, method: 'fuzzy' };
  }

  return { key: null, method: 'unresolved' };
}

/**
 * Sanitiza un array de claves musculares con auto-corrección y deduplicado.
 *
 * @param {any} arr
 * @param {object} [ctx] - Recolector opcional de correcciones/descartes para logging.
 * @returns {string[]}
 */
function sanitizeMuscleArray(arr, ctx = null) {
  if (!Array.isArray(arr)) return [];
  const out = [];
  for (const item of arr) {
    const { key, method } = correctMuscleKey(item);
    if (key) {
      if (!out.includes(key)) out.push(key);
      if (method !== 'exact' && ctx) ctx.corrections?.push(`"${item}" → "${key}" (${method})`);
    } else if (ctx) {
      ctx.discarded?.push(String(item));
    }
  }
  return out;
}

const EJERCICIO_ID_RE = /^wger-\d{1,4}$/i;

/**
 * Repara un plan de rutina completo garantizando los invariantes anatómicos.
 * Muta el plan in place y devuelve un reporte de correcciones.
 *
 * @param {object} plan
 * @returns {{ plan: object, corrections: string[], discarded: string[], droppedExercises: number }}
 */
function repairRoutinePlan(plan) {
  const ctx = { corrections: [], discarded: [] };
  let droppedExercises = 0;

  if (!plan || !Array.isArray(plan.dias)) {
    return { plan, corrections: ctx.corrections, discarded: ctx.discarded, droppedExercises };
  }

  for (const dia of plan.dias) {
    // Enfoque muscular del día (también se validaba nunca en el código original).
    dia.enfoque_muscular = sanitizeMuscleArray(dia.enfoque_muscular, ctx);

    if (!Array.isArray(dia.ejercicios)) { dia.ejercicios = []; continue; }

    const keep = [];
    for (const ej of dia.ejercicios) {
      ej.musculos_primarios   = sanitizeMuscleArray(ej.musculos_primarios, ctx);
      ej.musculos_secundarios = sanitizeMuscleArray(ej.musculos_secundarios, ctx);

      // Invariante: ≥1 primario. Si quedó vacío, heredar del enfoque del día.
      if (ej.musculos_primarios.length === 0) {
        if (dia.enfoque_muscular.length > 0) {
          ej.musculos_primarios = [dia.enfoque_muscular[0]];
          ctx.corrections.push(`ejercicio "${ej.nombre || 's/n'}": primario vacío → heredó "${dia.enfoque_muscular[0]}" del día.`);
        } else {
          // Sin forma segura de mapear: se descarta para no romper el SVG anatómico.
          droppedExercises++;
          ctx.discarded.push(`ejercicio "${ej.nombre || 's/n'}" sin músculo primario resoluble`);
          continue;
        }
      }

      // Formato de ejercicio_id (la validación contra catálogo real se hace en
      // exerciseCatalogValidator; aquí solo se garantiza el formato).
      if (!ej.ejercicio_id || !EJERCICIO_ID_RE.test(String(ej.ejercicio_id))) {
        const fixed = `wger-${Math.floor(Math.random() * 900 + 100)}`;
        ctx.corrections.push(`ejercicio "${ej.nombre || 's/n'}": ejercicio_id inválido → ${fixed} (placeholder, requiere reconciliación con catálogo).`);
        ej.ejercicio_id = fixed;
      }

      keep.push(ej);
    }
    dia.ejercicios = keep;
  }

  return { plan, corrections: ctx.corrections, discarded: ctx.discarded, droppedExercises };
}

module.exports = {
  normalize,
  correctMuscleKey,
  sanitizeMuscleArray,
  repairRoutinePlan,
  levenshtein,
};
