/**
 * @file services/fitness-service/src/controllers/nutritionController.js
 * @description Seguimiento nutricional real del socio (consumo diario + agua).
 * Todas las rutas requieren JWT (req.user.id lo inyecta jwtVerify).
 */

'use strict';

const nutritionLogModel       = require('../models/nutritionLogModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:nutritionController');

/** GET /api/v1/nutrition/today — Totales consumidos + agua + alimentos de hoy. */
async function getToday(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const [summary, entries] = await Promise.all([
      nutritionLogModel.getTodaySummary(usuarioId),
      nutritionLogModel.getTodayEntries(usuarioId),
    ]);
    return res.status(200).json({ success: true, data: { summary, entries }, error: null });
  } catch (err) {
    next(err);
  }
}

/** POST /api/v1/nutrition/food — Registra un alimento consumido hoy. */
async function logFood(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const {
      comida, nombreAlimento, cantidadGramos,
      calorias, proteinas, carbohidratos, grasas, codigoBarras,
    } = req.body || {};

    if (!nombreAlimento) {
      return res.status(400).json({ success: false, data: null, error: 'nombreAlimento es requerido.' });
    }

    const row = await nutritionLogModel.logFood(usuarioId, {
      comida, nombreAlimento, cantidadGramos,
      calorias, proteinas, carbohidratos, grasas, codigoBarras,
    });
    const summary = await nutritionLogModel.getTodaySummary(usuarioId);
    return res.status(201).json({ success: true, data: { row, summary }, error: null });
  } catch (err) {
    next(err);
  }
}

/** DELETE /api/v1/nutrition/food/:id — Quita un alimento consumido de hoy. */
async function deleteFood(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const ok = await nutritionLogModel.deleteFood(usuarioId, req.params.id);
    if (!ok) {
      return res.status(404).json({ success: false, data: null, error: 'Registro no encontrado.' });
    }
    const summary = await nutritionLogModel.getTodaySummary(usuarioId);
    return res.status(200).json({ success: true, data: { summary }, error: null });
  } catch (err) {
    next(err);
  }
}

/** POST /api/v1/nutrition/water — Suma agua (ml) al total de hoy. */
async function addWater(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const ml = parseInt(req.body?.ml, 10);
    if (!Number.isFinite(ml) || ml <= 0 || ml > 5000) {
      return res.status(400).json({ success: false, data: null, error: 'ml debe ser un entero entre 1 y 5000.' });
    }
    const totalMl = await nutritionLogModel.addWater(usuarioId, ml);
    return res.status(200).json({ success: true, data: { agua_ml: totalMl }, error: null });
  } catch (err) {
    next(err);
  }
}

module.exports = { getToday, logFood, deleteFood, addWater };
