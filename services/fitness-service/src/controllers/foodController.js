/**
 * @file services/fitness-service/src/controllers/foodController.js
 * @description Controlador para buscar alimentos en catalogo_alimentos (Open Food Facts)
 * con fallback de alta disponibilidad para garantizar una experiencia fluida e instantánea.
 */

'use strict';

const { query } = require('../config/database');   // pg directo (svc_fitness)
const { sanitizeLikeQuery, sanitizeBarcode } = require('../utils/postgrestSanitizer');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:foodController');

// Catálogo precargado en memoria (Open Food Facts standards) como fallback de alta velocidad
const FALLBACK_OPEN_FOOD_FACTS = [
  {
    codigo_barras: '7501008012345',
    nombre: 'Avena Integral en Hojuelas',
    marca: 'Quaker',
    calorias_100g: 370,
    proteinas_100g: 13.5,
    carbohidratos_100g: 66.0,
    grasas_100g: 7.0,
  },
  {
    codigo_barras: '7501000111111',
    nombre: 'Pechuga de Pollo Fresca sin Piel',
    marca: 'Bachoco',
    calorias_100g: 165,
    proteinas_100g: 31.0,
    carbohidratos_100g: 0.0,
    grasas_100g: 3.6,
  },
  {
    codigo_barras: '7501020304050',
    nombre: 'Atún en Agua en Trozos',
    marca: 'Dolores',
    calorias_100g: 110,
    proteinas_100g: 26.0,
    carbohidratos_100g: 0.0,
    grasas_100g: 0.8,
  },
  {
    codigo_barras: '7501099998888',
    nombre: 'Arroz Súper Extra Integral',
    marca: 'Verde Valle',
    calorias_100g: 350,
    proteinas_100g: 7.5,
    carbohidratos_100g: 77.0,
    grasas_100g: 2.2,
  },
  {
    codigo_barras: '7501234567890',
    nombre: 'Proteína Whey Gold Standard 100% Isolate',
    marca: 'Optimum Nutrition',
    calorias_100g: 388,
    proteinas_100g: 78.0,
    carbohidratos_100g: 9.7,
    grasas_100g: 3.2,
  },
  {
    codigo_barras: '7501111122222',
    nombre: 'Claras de Huevo Pasteurizadas Líquidas',
    marca: 'San Juan',
    calorias_100g: 52,
    proteinas_100g: 11.0,
    carbohidratos_100g: 0.7,
    grasas_100g: 0.2,
  },
  {
    codigo_barras: '0000000001234',
    nombre: 'Plátano Tabasco Fresco',
    marca: 'Natural Orgánico',
    calorias_100g: 89,
    proteinas_100g: 1.1,
    carbohidratos_100g: 22.8,
    grasas_100g: 0.3,
  },
  {
    codigo_barras: '7501444455555',
    nombre: 'Crema de Cacahuate Natural sin Azúcar',
    marca: 'Aladino',
    calorias_100g: 588,
    proteinas_100g: 25.0,
    carbohidratos_100g: 20.0,
    grasas_100g: 50.0,
  },
  {
    codigo_barras: '7501666677777',
    nombre: 'Almendras Tostadas Naturales sin Sal',
    marca: 'Kirkland Signature',
    calorias_100g: 579,
    proteinas_100g: 21.1,
    carbohidratos_100g: 21.6,
    grasas_100g: 49.9,
  },
  {
    codigo_barras: '7501888899999',
    nombre: 'Yogurt Griego Fresa sin Azúcar Añadida',
    marca: 'Chobani',
    calorias_100g: 59,
    proteinas_100g: 10.0,
    carbohidratos_100g: 3.6,
    grasas_100g: 0.2,
  },
];

/**
 * GET /api/v1/foods/search?q=avena
 * Busca alimentos por nombre o marca en la base de datos o en memoria.
 */
/**
 * Búsqueda EN VIVO contra la API pública de Open Food Facts (es.openfoodfacts.org).
 * Se usa cuando `catalogo_alimentos` no está poblada (o no matchea): así el socio
 * puede buscar en el catálogo completo de OFF y no solo en el fallback fijo.
 * Best-effort: ante cualquier fallo/timeout devuelve [].
 */
async function searchOpenFoodFactsLive(term) {
  const url = 'https://es.openfoodfacts.org/cgi/search.pl'
    + `?search_terms=${encodeURIComponent(term)}`
    + '&search_simple=1&action=process&json=1&page_size=30'
    + '&fields=code,product_name,product_name_es,brands,nutriments';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'GymPro/1.0 (fitness-service)' },
    });
    if (!res.ok) return [];
    const data = await res.json();
    const products = Array.isArray(data.products) ? data.products : [];
    const seen = new Set();
    const out = [];
    for (const p of products) {
      const nombre = (p.product_name_es || p.product_name || '').trim();
      if (!nombre) continue;
      const key = nombre.toLowerCase();
      if (seen.has(key)) continue;
      const n = p.nutriments || {};
      const kcal = Number(n['energy-kcal_100g'] ?? n['energy-kcal'] ?? 0);
      if (!(kcal > 0)) continue; // descarta productos sin datos nutricionales útiles
      seen.add(key);
      out.push({
        codigo_barras: String(p.code || '').trim() || '0000000000000',
        nombre: nombre.slice(0, 120),
        marca: String(p.brands || '').split(',')[0].trim() || 'Genérico',
        calorias_100g: kcal,
        proteinas_100g: Number(n.proteins_100g ?? 0),
        carbohidratos_100g: Number(n.carbohydrates_100g ?? 0),
        grasas_100g: Number(n.fat_100g ?? 0),
        es_open_food_facts: true,
      });
    }
    return out;
  } catch (err) {
    logger.warn('Open Food Facts live search falló', { error: err.message });
    return [];
  } finally {
    clearTimeout(timer);
  }
}

async function searchFoods(req, res, next) {
  try {
    // ── Saneamiento anti-inyección PostgREST ────────────────────────────────
    // El término se neutraliza antes de interpolarse en la expresión .or().
    const safeQuery = sanitizeLikeQuery(req.query.q || '');
    logger.info('Buscando alimentos en Open Food Facts catalog', { query: safeQuery });

    if (!safeQuery) {
      return res.status(200).json({ success: true, data: [], error: null });
    }

    let results = [];
    try {
      const { rows } = await query(
        `SELECT * FROM catalogo_alimentos WHERE (nombre ILIKE $1 OR marca ILIKE $1) LIMIT 30`,
        [`%${safeQuery}%`],
      );
      if (rows.length > 0) results = rows;
    } catch (dbErr) {
      logger.warn('Error al consultar catalogo_alimentos en Supabase, usando fallback', { error: dbErr.message });
    }

    // Si la tabla local no tiene resultados, buscamos EN VIVO en Open Food Facts
    // (catálogo completo) antes de caer al fallback fijo de emergencia.
    if (results.length === 0) {
      results = await searchOpenFoodFactsLive(safeQuery);
    }

    if (results.length === 0) {
      const qLower = safeQuery.toLowerCase();
      results = FALLBACK_OPEN_FOOD_FACTS.filter(
        (item) =>
          item.nombre.toLowerCase().includes(qLower) ||
          item.marca.toLowerCase().includes(qLower) ||
          item.codigo_barras.includes(qLower)
      );
    }

    return res.status(200).json({
      success: true,
      data:    results,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/v1/foods/barcode/:code
 * Obtiene un alimento por su código de barras.
 */
async function getFoodByBarcode(req, res, next) {
  try {
    const code = sanitizeBarcode(req.params.code);
    logger.info('Buscando alimento por código de barras', { code });

    if (!code) {
      return res.status(400).json({ success: false, data: null, error: 'Código de barras inválido.' });
    }

    let food = null;
    try {
      const { rows } = await query(
        `SELECT * FROM catalogo_alimentos WHERE codigo_barras = $1 LIMIT 1`,
        [code],
      );
      if (rows[0]) food = rows[0];
    } catch (dbErr) {
      logger.warn('Error en DB al buscar por barcode, usando fallback', { error: dbErr.message });
    }

    if (!food) {
      food = FALLBACK_OPEN_FOOD_FACTS.find((f) => f.codigo_barras === code);
    }

    if (!food) {
      return res.status(404).json({
        success: false,
        data: null,
        error: `No se encontró el alimento con código de barras ${code}`,
      });
    }

    return res.status(200).json({
      success: true,
      data:    food,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  searchFoods,
  getFoodByBarcode,
  FALLBACK_OPEN_FOOD_FACTS,
};
