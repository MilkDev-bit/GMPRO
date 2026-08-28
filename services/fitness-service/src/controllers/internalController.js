/**
 * @file services/fitness-service/src/controllers/internalController.js
 * @description Endpoints internos M2M para proveer contexto de fitness al ai-service.
 */

'use strict';

const progressModel           = require('../models/progressModel');
const { query }               = require('../config/database');   // pg directo (svc_fitness)
const { sanitizeLikeQuery, sanitizeBarcode } = require('../utils/postgrestSanitizer');
const { FALLBACK_OPEN_FOOD_FACTS } = require('./foodController');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:internalController');

/**
 * GET /api/v1/internal/user-context?userId=UUID
 * Retorna resumen consolido de progreso y rutinas para alimentar el prompt del LLM.
 */
async function getUserContext(req, res, next) {
  try {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({
        success: false, data: null, error: 'El parámetro userId es requerido.',
      });
    }

    const summary = await progressModel.getUserContextSummary(userId);
    return res.status(200).json({
      success: true,
      data:    summary,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/internal/foods/verify
 * Verifica códigos de barras y/o nombre contra catalogo_alimentos (con fallback en
 * memoria). Consumido por ai-service para reconciliar los alimentos que sugiere la IA.
 *
 * Body: { barcodes?: string[], name?: string }
 * Respuesta: { by_barcode: { <code>: food }, by_name: food|null }
 */
/**
 * Búsqueda EN VIVO por nombre en Open Food Facts (es). Devuelve el primer producto
 * con datos nutricionales útiles, mapeado a la forma de catalogo_alimentos. Best-effort:
 * ante fallo/timeout devuelve null. Refuerza la cobertura del catálogo local.
 */
async function offByName(name) {
  const url = 'https://es.openfoodfacts.org/cgi/search.pl'
    + `?search_terms=${encodeURIComponent(name)}`
    + '&search_simple=1&action=process&json=1&page_size=5'
    + '&fields=code,product_name,product_name_es,brands,nutriments';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': 'GymPro/1.0 (fitness-service)' },
    });
    if (!res.ok) return null;
    const data = await res.json();
    for (const p of (Array.isArray(data.products) ? data.products : [])) {
      const nombre = (p.product_name_es || p.product_name || '').trim();
      const n = p.nutriments || {};
      const kcal = Number(n['energy-kcal_100g'] ?? n['energy-kcal'] ?? 0);
      if (!nombre || !(kcal > 0)) continue;
      return {
        codigo_barras: String(p.code || '').trim() || null,
        nombre: nombre.slice(0, 120),
        marca: String(p.brands || '').split(',')[0].trim() || 'Genérico',
        calorias_100g: kcal,
        proteinas_100g: Number(n.proteins_100g ?? 0),
        carbohidratos_100g: Number(n.carbohydrates_100g ?? 0),
        grasas_100g: Number(n.fat_100g ?? 0),
      };
    }
    return null;
  } catch (err) {
    logger.warn('verifyFoods: OFF-live por nombre falló', { name, error: err.message });
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function verifyFoods(req, res, next) {
  try {
    const { barcodes = [], name = null } = req.body || {};
    const result = { by_barcode: {}, by_name: null };

    const codes = Array.isArray(barcodes)
      ? [...new Set(barcodes.map(sanitizeBarcode).filter(Boolean))].slice(0, 100)
      : [];

    // ── 1. Verificación batch por código de barras ──────────────────────────
    if (codes.length > 0) {
      let rows = [];
      try {
        const r = await query(`SELECT * FROM catalogo_alimentos WHERE codigo_barras = ANY($1)`, [codes]);
        rows = r.rows;
      } catch (dbErr) {
        logger.warn('verifyFoods: fallo consultando catalogo_alimentos, usando fallback', { error: dbErr.message });
      }
      for (const food of rows) result.by_barcode[String(food.codigo_barras)] = food;

      // Completar con el catálogo en memoria lo que la DB no cubrió.
      for (const code of codes) {
        if (!result.by_barcode[code]) {
          const hit = FALLBACK_OPEN_FOOD_FACTS.find((f) => f.codigo_barras === code);
          if (hit) result.by_barcode[code] = hit;
        }
      }
    }

    // ── 2. Búsqueda por nombre (saneada) ────────────────────────────────────
    const safeName = sanitizeLikeQuery(name);
    if (safeName) {
      let found = null;
      try {
        const r = await query(`SELECT * FROM catalogo_alimentos WHERE (nombre ILIKE $1 OR marca ILIKE $1) LIMIT 1`, [`%${safeName}%`]);
        if (r.rows[0]) found = r.rows[0];
      } catch (dbErr) {
        logger.warn('verifyFoods: fallo búsqueda por nombre, usando fallback', { error: dbErr.message });
      }
      // Refuerzo de cobertura: si el catálogo local no matchea, buscamos EN VIVO en
      // Open Food Facts antes de caer al fallback fijo. Así casi cualquier alimento
      // que nombre la IA se resuelve con macros reales (no queda "estimado" en 0).
      if (!found) {
        found = await offByName(safeName);
      }
      if (!found) {
        const qLower = safeName.toLowerCase();
        found = FALLBACK_OPEN_FOOD_FACTS.find(
          (f) => f.nombre.toLowerCase().includes(qLower) || f.marca.toLowerCase().includes(qLower)
        ) || null;
      }
      result.by_name = found;
    }

    return res.status(200).json({ success: true, data: result, error: null });
  } catch (err) {
    next(err);
  }
}

// ── Resolución de imágenes de ejercicios (wger) por nombre ────────────────────
// Cache en memoria del catálogo (pequeño). Se recarga cada hora.
let _catalogCache = null;
let _catalogCacheAt = 0;
const CATALOG_TTL_MS = 60 * 60 * 1000;

const _STOP = new Set(['de', 'con', 'en', 'la', 'el', 'los', 'las', 'y', 'del', 'para', 'al', 'un', 'una', 'sobre']);

function _normTokens(s) {
  return String(s || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // quita acentos
    .toLowerCase().replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2 && !_STOP.has(w));
}

async function _loadCatalog() {
  const now = Date.now();
  if (_catalogCache && now - _catalogCacheAt < CATALOG_TTL_MS) return _catalogCache;
  const r = await query(
    `SELECT id_wger, nombre, nombre_en, imagen_url, video_url, gif_url, thumbnail_url
       FROM catalogo_ejercicios
      WHERE COALESCE(imagen_url, thumbnail_url, video_url, gif_url) IS NOT NULL`,
    [],
  );
  _catalogCache = r.rows.map((row) => ({
    ...row,
    _tok: new Set([..._normTokens(row.nombre), ..._normTokens(row.nombre_en)]),
  }));
  _catalogCacheAt = now;
  return _catalogCache;
}

/**
 * POST /api/v1/internal/exercises/images
 * Body: { names: string[] }
 * Resuelve la imagen/video real de wger para cada nombre de ejercicio (match por
 * solapamiento de tokens contra catalogo_ejercicios). Consumido por ai-service
 * para enriquecer la rutina generada. Best-effort: nombres sin match se omiten.
 * Respuesta: { <name>: { id_wger, nombre, imagen_url, video_url, thumbnail_url } }
 */
async function resolveExerciseImages(req, res, next) {
  try {
    const names = Array.isArray(req.body?.names) ? req.body.names.slice(0, 80) : [];
    const out = {};
    if (names.length === 0) return res.status(200).json({ success: true, data: out, error: null });

    let catalog = [];
    try {
      catalog = await _loadCatalog();
    } catch (e) {
      logger.warn('resolveExerciseImages: no se pudo cargar catalogo_ejercicios', { error: e.message });
      return res.status(200).json({ success: true, data: out, error: null });
    }
    if (catalog.length === 0) {
      logger.warn('resolveExerciseImages: catalogo_ejercicios vacío o sin imágenes (¿falta correr el seed?)');
      return res.status(200).json({ success: true, data: out, error: null });
    }

    for (const name of names) {
      const qtok = _normTokens(name);
      if (!qtok.length) continue;
      let best = null;
      let bestScore = 0;
      for (const row of catalog) {
        let shared = 0;
        for (const t of qtok) if (row._tok.has(t)) shared++;
        if (shared === 0) continue;
        const score = shared / Math.max(qtok.length, row._tok.size || 1);
        if (score > bestScore) { bestScore = score; best = row; }
      }
      if (best && bestScore >= 0.34) {
        out[name] = {
          id_wger: best.id_wger,
          nombre: best.nombre,
          imagen_url: best.imagen_url,
          video_url: best.video_url,
          gif_url: best.gif_url,
          thumbnail_url: best.thumbnail_url,
        };
      }
    }
    return res.status(200).json({ success: true, data: out, error: null });
  } catch (err) {
    next(err);
  }
}

module.exports = { getUserContext, verifyFoods, resolveExerciseImages };
