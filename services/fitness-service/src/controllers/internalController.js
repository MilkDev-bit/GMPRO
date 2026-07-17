/**
 * @file services/fitness-service/src/controllers/internalController.js
 * @description Endpoints internos M2M para proveer contexto de fitness al ai-service.
 */

'use strict';

const progressModel           = require('../models/progressModel');
const { getSupabaseClient }   = require('../config/database');
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
async function verifyFoods(req, res, next) {
  try {
    const { barcodes = [], name = null } = req.body || {};
    const result = { by_barcode: {}, by_name: null };

    const codes = Array.isArray(barcodes)
      ? [...new Set(barcodes.map(sanitizeBarcode).filter(Boolean))].slice(0, 100)
      : [];

    let db = null;
    try { db = getSupabaseClient(); } catch (_) { db = null; }

    // ── 1. Verificación batch por código de barras ──────────────────────────
    if (codes.length > 0) {
      let rows = [];
      if (db) {
        try {
          const { data, error } = await db
            .from('catalogo_alimentos')
            .select('*')
            .in('codigo_barras', codes);
          if (!error && Array.isArray(data)) rows = data;
        } catch (dbErr) {
          logger.warn('verifyFoods: fallo consultando catalogo_alimentos, usando fallback', { error: dbErr.message });
        }
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
      if (db) {
        try {
          const { data, error } = await db
            .from('catalogo_alimentos')
            .select('*')
            .or(`nombre.ilike.%${safeName}%,marca.ilike.%${safeName}%`)
            .limit(1);
          if (!error && data && data[0]) found = data[0];
        } catch (dbErr) {
          logger.warn('verifyFoods: fallo búsqueda por nombre, usando fallback', { error: dbErr.message });
        }
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

module.exports = { getUserContext, verifyFoods };
