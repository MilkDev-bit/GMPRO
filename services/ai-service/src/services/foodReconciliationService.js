/**
 * @file services/ai-service/src/services/foodReconciliationService.js
 * @description Reconciliador anti-alucinación de códigos de barras (Eje 2 de la auditoría).
 *
 * PROBLEMA: la IA puede inventar un `codigo_barras` que no existe en
 * `catalogo_alimentos` (Supabase) ni en Open Food Facts. Si ese plan se guarda tal
 * cual, el escáner de la app no resolverá el producto y el usuario verá datos falsos.
 *
 * ESTRATEGIA (en cascada, de mayor a menor confianza):
 *   1. Verificar el barcode en el catálogo local (batch, una sola query .in()).
 *   2. Si no está, consultar la API pública de Open Food Facts (timeout corto).
 *   3. Si tampoco, buscar por NOMBRE en el catálogo local y adoptar ese barcode real.
 *   4. Si nada resuelve → se DEGRADA: codigo_barras=null, es_open_food_facts=false,
 *      verificado='estimado_ia'. Se conservan los macros como estimación etiquetada,
 *      nunca como un producto escaneable inexistente.
 *
 * Inyección de dependencias (desacoplado de la infra concreta):
 *   • lookupByBarcodes(codes[]) => Promise<Map<code, food>>  (catálogo local / fitness-service)
 *   • lookupByName(name)        => Promise<food|null>        (búsqueda difusa en catálogo)
 *   • Open Food Facts se resuelve con el cliente incluido (fetchOpenFoodFactsProduct).
 */

'use strict';

const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('ai-service:foodReconciliation');

/** Normaliza un código de barras a solo dígitos. */
function normalizeBarcode(code) {
  return String(code || '').replace(/\D/g, '');
}

/**
 * Consulta un producto en la API pública de Open Food Facts (v2).
 * @param {string} barcode
 * @param {number} [timeoutMs=1500]
 * @returns {Promise<object|null>} Macros normalizados por 100 g o null.
 */
async function fetchOpenFoodFactsProduct(barcode, timeoutMs = 1500) {
  const code = normalizeBarcode(barcode);
  if (code.length < 8) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const url = `https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,brands,nutriments`;
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'GymPro-AI/1.0 (nutrition reconciliation)' },
    });
    if (!resp.ok) return null;
    const json = await resp.json();
    if (json.status !== 1 || !json.product) return null;

    const n = json.product.nutriments || {};
    return {
      codigo_barras:      code,
      nombre:             json.product.product_name || 'Producto Open Food Facts',
      marca:              json.product.brands || null,
      calorias_100g:      Number(n['energy-kcal_100g']) || 0,
      proteinas_100g:     Number(n.proteins_100g) || 0,
      carbohidratos_100g: Number(n.carbohydrates_100g) || 0,
      grasas_100g:        Number(n.fat_100g) || 0,
      es_open_food_facts: true,
      verificado:         'open_food_facts',
    };
  } catch (err) {
    logger.debug('Open Food Facts no disponible o timeout', { barcode: code, error: err.message });
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Sobrescribe los macros del alimento con la fuente verificada. */
function applyVerifiedSource(food, source, verificado) {
  food.codigo_barras      = source.codigo_barras;
  food.nombre             = source.nombre || food.nombre;
  food.marca              = source.marca ?? food.marca ?? null;
  food.calorias_100g      = source.calorias_100g;
  food.proteinas_100g     = source.proteinas_100g;
  food.carbohidratos_100g = source.carbohidratos_100g;
  food.grasas_100g        = source.grasas_100g;
  food.es_open_food_facts = true;
  food.verificado         = verificado;
}

/**
 * Reconcilia todos los alimentos de un plan nutricional de la IA.
 *
 * @param {object} plan
 * @param {object} deps
 * @param {(codes:string[]) => Promise<Map<string, object>>} deps.lookupByBarcodes
 * @param {(name:string)   => Promise<object|null>}          [deps.lookupByName]
 * @param {boolean} [deps.useOpenFoodFacts=true]
 * @param {number}  [deps.offTimeoutMs=1500]
 * @returns {Promise<{ plan: object, verified: number, degraded: number, corrections: string[] }>}
 */
async function reconcilePlanFoods(plan, deps = {}) {
  const {
    lookupByBarcodes,
    lookupByName,
    useOpenFoodFacts = true,
    offTimeoutMs     = 1500,
  } = deps;

  const corrections = [];
  let verified = 0, degraded = 0;

  const meals = plan && Array.isArray(plan.comidas) ? plan.comidas : [];
  const allFoods = [];
  for (const meal of meals) {
    if (Array.isArray(meal.alimentos)) allFoods.push(...meal.alimentos);
  }
  if (allFoods.length === 0) return { plan, verified, degraded, corrections };

  // ── 1. Verificación batch contra el catálogo local ──────────────────────────
  const barcodes = [...new Set(allFoods.map((f) => normalizeBarcode(f.codigo_barras)).filter(Boolean))];
  let catalogMap = new Map();
  if (typeof lookupByBarcodes === 'function' && barcodes.length > 0) {
    try {
      catalogMap = await lookupByBarcodes(barcodes) || new Map();
    } catch (err) {
      logger.warn('Fallo verificando barcodes en catálogo local', { error: err.message });
    }
  }

  // ── 2-4. Resolver alimento por alimento ─────────────────────────────────────
  // Resuelve UN alimento (barcode local → OFF por barcode → nombre). Devuelve
  // 'verified' | 'degraded'. Es async y sin efectos compartidos peligrosos: los
  // push a `corrections` sobre un array son seguros en el bucle de eventos de Node.
  const resolveFood = async (food) => {
    const code = normalizeBarcode(food.codigo_barras);

    // (1) Catálogo local por barcode
    if (code && catalogMap.has(code)) {
      applyVerifiedSource(food, { ...catalogMap.get(code), codigo_barras: code }, 'catalogo_local');
      return 'verified';
    }

    // (2) Open Food Facts por barcode
    if (useOpenFoodFacts && code) {
      const off = await fetchOpenFoodFactsProduct(code, offTimeoutMs);
      if (off) {
        applyVerifiedSource(food, off, 'open_food_facts');
        return 'verified';
      }
    }

    // (3) Búsqueda por nombre (catálogo local → OFF en vivo, dentro del fitness-service)
    if (typeof lookupByName === 'function' && food.nombre) {
      try {
        const byName = await lookupByName(food.nombre);
        // Aceptamos el match aunque no traiga barcode (OFF a veces no lo da): lo que
        // importa son los macros. Con calorías válidas, lo damos por verificado.
        if (byName && Number(byName.calorias_100g) > 0) {
          applyVerifiedSource(food, byName, 'coincidencia_por_nombre');
          return 'verified';
        }
      } catch (err) {
        logger.debug('Búsqueda por nombre falló', { nombre: food.nombre, error: err.message });
      }
    }

    // (4) Degradación controlada: no persistir un producto inexistente
    corrections.push(`"${food.nombre || 's/n'}": no verificable → macros estimados.`);
    food.codigo_barras      = null;
    food.es_open_food_facts = false;
    food.verificado         = 'estimado_ia';
    return 'degraded';
  };

  // PARALELO con límite de concurrencia: antes se resolvía en serie y cada OFF (≤5s)
  // se sumaba, haciendo lenta la generación. En tandas de 6 baja drásticamente.
  const CONCURRENCY = 6;
  for (let i = 0; i < allFoods.length; i += CONCURRENCY) {
    const results = await Promise.all(allFoods.slice(i, i + CONCURRENCY).map(resolveFood));
    for (const r of results) (r === 'verified') ? verified++ : degraded++;
  }

  plan._food_check = { verificados: verified, degradados: degraded, total: allFoods.length };
  return { plan, verified, degraded, corrections };
}

module.exports = {
  normalizeBarcode,
  fetchOpenFoodFactsProduct,
  reconcilePlanFoods,
};
