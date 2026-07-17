/**
 * @file services/fitness-service/src/routes/internalRoutes.js
 * @description Rutas internas M2M para compartir contexto de usuario con ai-service.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const internalController         = require('../controllers/internalController');

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

// GET /api/v1/internal/user-context?userId=UUID -> Resumen de progreso y rutinas
router.get('/user-context', internalController.getUserContext);

// POST /api/v1/internal/foods/verify -> Verifica barcodes/nombre contra el catálogo
router.post(
  '/foods/verify',
  [
    body('barcodes').optional().isArray({ max: 100 }).withMessage('barcodes debe ser un array (máx 100).'),
    body('name').optional().isString().isLength({ max: 120 }),
  ],
  validate,
  internalController.verifyFoods
);

module.exports = router;
