/**
 * @file services/fitness-service/src/routes/internalRoutes.js
 * @description Rutas internas M2M para compartir contexto de usuario con ai-service.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const internalController         = require('../controllers/internalController');
const emailController            = require('../controllers/emailController');

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

// POST /api/v1/internal/exercises/images -> Resuelve imagen/video de wger por nombre
router.post(
  '/exercises/images',
  [
    body('names').isArray({ max: 80 }).withMessage('names debe ser un array (máx 80).'),
  ],
  validate,
  internalController.resolveExerciseImages
);

// ── Correos transaccionales (cola BullMQ) ───────────────────────────────────
// GET /api/v1/internal/emails/templates
router.get('/emails/templates', emailController.listTemplates);

// POST /api/v1/internal/emails/enqueue → 202 Accepted (entrega asíncrona)
router.post(
  '/emails/enqueue',
  [
    body('to').isEmail().withMessage('Destinatario inválido.'),
    body('template').isString().notEmpty().withMessage('Plantilla requerida.'),
    body('vars').optional().isObject(),
    body('delayMs').optional().isInt({ min: 0, max: 7 * 24 * 3600 * 1000 }),
    body('dedupeKey').optional().isString().isLength({ max: 120 }),
  ],
  validate,
  emailController.enqueueTransactionalEmail
);

module.exports = router;
