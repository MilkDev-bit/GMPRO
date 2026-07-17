/**
 * @file services/fitness-service/src/routes/routineRoutes.js
 * @description Rutas para gestión de rutinas personalizadas.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const routineController          = require('../controllers/routineController');

const router = Router();

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false, data: null,
      error: errors.array().map((e) => `${e.path}: ${e.msg}`).join(' | '),
    });
  }
  next();
}

// GET /api/v1/routines -> Lista rutinas del usuario
router.get('/', routineController.getRoutines);

// POST /api/v1/routines -> Crea nueva rutina
router.post(
  '/',
  [
    body('nombre').notEmpty().withMessage('El nombre de la rutina es requerido.'),
    body('ejercicios').optional().isArray().withMessage('Los ejercicios deben ser un arreglo.'),
  ],
  validate,
  routineController.createRoutine
);

// DELETE /api/v1/routines/:id -> Elimina una rutina
router.delete('/:id', routineController.deleteRoutine);

module.exports = router;
