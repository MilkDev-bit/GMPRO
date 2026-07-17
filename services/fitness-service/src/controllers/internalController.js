/**
 * @file services/fitness-service/src/controllers/internalController.js
 * @description Endpoints internos M2M para proveer contexto de fitness al ai-service.
 */

'use strict';

const progressModel           = require('../models/progressModel');
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

module.exports = { getUserContext };
