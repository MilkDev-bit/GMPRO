/**
 * @file services/fitness-service/src/controllers/exerciseController.js
 * @description Controladores para consulta y filtrado del catálogo de ejercicios.
 */

'use strict';

const exerciseModel           = require('../models/exerciseModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:exerciseController');

/**
 * GET /api/v1/exercises
 * Lista ejercicios con filtros por grupo muscular, dificultad, equipamiento y paginación.
 */
async function listExercises(req, res, next) {
  try {
    const { muscleGroup, difficulty, equipment, page, pageSize } = req.query;

    const result = await exerciseModel.getExercises({
      muscleGroup,
      difficulty,
      equipment,
      page,
      pageSize,
    }, req.redisClient);

    return res.status(200).json({
      success: true,
      data:    result,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/v1/exercises/:id
 * Obtiene el detalle de un ejercicio por su ID.
 */
async function getExerciseDetail(req, res, next) {
  try {
    const { id } = req.params;
    const exercise = await exerciseModel.getExerciseById(id);

    if (!exercise) {
      return res.status(404).json({
        success: false, data: null, error: 'Ejercicio no encontrado en el catálogo.',
      });
    }

    return res.status(200).json({
      success: true,
      data:    exercise,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  listExercises,
  getExerciseDetail,
};
