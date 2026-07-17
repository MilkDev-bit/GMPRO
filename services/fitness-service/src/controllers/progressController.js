/**
 * @file services/fitness-service/src/controllers/progressController.js
 * @description Controladores para seguimiento físico (peso, grasa, medidas corporales).
 */

'use strict';

const progressModel           = require('../models/progressModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:progressController');

/**
 * GET /api/v1/progress
 * Obtiene el historial de mediciones físicas del usuario autenticado.
 */
async function getProgressHistory(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const limit     = parseInt(req.query.limit || '20', 10);

    const logs = await progressModel.getPhysicalProgress(usuarioId, limit);
    return res.status(200).json({
      success: true,
      data:    logs,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/progress
 * Registra una nueva medición corporal.
 */
async function recordProgress(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const { peso_kg, porcentaje_grasa, masa_muscular_kg, medidas, notas } = req.body;

    if (!peso_kg || isNaN(peso_kg) || peso_kg <= 0) {
      return res.status(400).json({
        success: false, data: null, error: 'El peso en kg (peso_kg) es obligatorio y debe ser mayor a 0.',
      });
    }

    const log = await progressModel.recordPhysicalProgress({
      usuario_id: usuarioId,
      peso_kg: parseFloat(peso_kg),
      porcentaje_grasa: porcentaje_grasa ? parseFloat(porcentaje_grasa) : null,
      masa_muscular_kg: masa_muscular_kg ? parseFloat(masa_muscular_kg) : null,
      medidas,
      notas,
    });

    return res.status(201).json({
      success: true,
      data:    log,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getProgressHistory,
  recordProgress,
};
