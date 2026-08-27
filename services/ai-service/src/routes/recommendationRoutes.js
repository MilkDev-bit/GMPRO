/**
 * @file services/ai-service/src/routes/recommendationRoutes.js
 * @description Rutas para generación de recomendaciones estructuradas de entrenamiento.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const recommendationController   = require('../controllers/recommendationController');

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

// POST /api/v1/recommendations/routine -> Genera un plan de entrenamiento estructurado
router.post(
  '/routine',
  [
    body('objetivo').optional().isString(),
    body('diasPorSemana').optional().isInt({ min: 1, max: 7 }),
    body('nivel').optional().isString(),
    body('pesoKg').optional().isNumeric(),
    body('estaturaCm').optional().isNumeric(),
    body('edad').optional().isInt({ min: 12, max: 100 }),
    body('actividad').optional().isString(),
  ],
  validate,
  recommendationController.generateRoutinePlan
);

// POST /api/v1/recommendations/diet -> Genera un plan de nutrición estructurado con Open Food Facts
router.post(
  '/diet',
  [
    body('objetivo').optional().isString(),
    body('pesoKg').optional().isNumeric(),
    body('estaturaCm').optional().isNumeric(),
    body('ingredientes').optional().isString().isLength({ max: 600 }),
  ],
  validate,
  recommendationController.generateDietPlan
);

module.exports = router;
