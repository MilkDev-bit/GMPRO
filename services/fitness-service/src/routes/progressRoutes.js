/**
 * @file services/fitness-service/src/routes/progressRoutes.js
 * @description Rutas para seguimiento físico y antropometría.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const progressController         = require('../controllers/progressController');

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

// GET /api/v1/progress -> Historial de mediciones
router.get('/', progressController.getProgressHistory);

// POST /api/v1/progress -> Registrar nueva medición
router.post(
  '/',
  [
    body('peso_kg').isFloat({ min: 20, max: 500 }).withMessage('Peso inválido.'),
    body('porcentaje_grasa').optional({ nullable: true }).isFloat({ min: 1, max: 70 }),
  ],
  validate,
  progressController.recordProgress
);

module.exports = router;
