/**
 * @file services/fitness-service/src/routes/nutritionRoutes.js
 * @description Rutas del diario nutricional real (consumo diario + agua). JWT.
 */

'use strict';

const { Router }                 = require('express');
const { body, param, validationResult } = require('express-validator');
const nutritionController        = require('../controllers/nutritionController');

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

// GET /api/v1/nutrition/today -> Totales consumidos + agua + alimentos de hoy
router.get('/today', nutritionController.getToday);

// POST /api/v1/nutrition/food -> Registra un alimento consumido hoy
router.post(
  '/food',
  [
    body('nombreAlimento').isString().notEmpty().isLength({ max: 300 }),
    body('cantidadGramos').optional().isFloat({ min: 0 }),
    body('comida').optional().isString(),
    body('calorias').optional().isFloat({ min: 0 }),
    body('proteinas').optional().isFloat({ min: 0 }),
    body('carbohidratos').optional().isFloat({ min: 0 }),
    body('grasas').optional().isFloat({ min: 0 }),
    body('codigoBarras').optional().isString().isLength({ max: 30 }),
  ],
  validate,
  nutritionController.logFood
);

// DELETE /api/v1/nutrition/food/:id -> Quita un alimento consumido de hoy
router.delete(
  '/food/:id',
  [param('id').isUUID().withMessage('id inválido')],
  validate,
  nutritionController.deleteFood
);

// POST /api/v1/nutrition/water -> Suma agua (ml) al total de hoy
router.post(
  '/water',
  [body('ml').isInt({ min: 1, max: 5000 })],
  validate,
  nutritionController.addWater
);

module.exports = router;
