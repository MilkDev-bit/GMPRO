/**
 * @file services/fitness-service/src/controllers/routineController.js
 * @description Controladores para creación, listado y eliminación de rutinas.
 */

'use strict';

const routineModel            = require('../models/routineModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:routineController');

/**
 * GET /api/v1/routines
 * Obtiene todas las rutinas del usuario autenticado.
 */
async function getRoutines(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const routines  = await routineModel.getUserRoutines(usuarioId);

    return res.status(200).json({
      success: true,
      data:    routines,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/routines
 * Crea una nueva rutina personalizada.
 */
async function createRoutine(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const { nombre, descripcion, nivel, ejercicios } = req.body;

    if (!nombre) {
      return res.status(400).json({
        success: false, data: null, error: 'El nombre de la rutina es obligatorio.',
      });
    }

    const rutina = await routineModel.createRoutine({
      usuario_id: usuarioId,
      nombre,
      descripcion,
      nivel,
      ejercicios,
    });

    return res.status(201).json({
      success: true,
      data:    rutina,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * DELETE /api/v1/routines/:id
 * Elimina una rutina propiedad del usuario.
 */
async function deleteRoutine(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const { id }    = req.params;

    const deleted = await routineModel.deleteRoutine(id, usuarioId);
    if (!deleted) {
      return res.status(404).json({
        success: false, data: null, error: 'Rutina no encontrada o no pertenece al usuario.',
      });
    }

    logger.info('Rutina eliminada', { rutinaId: id, usuarioId });
    return res.status(200).json({
      success: true,
      data:    { id, eliminado: true },
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getRoutines,
  createRoutine,
  deleteRoutine,
};
