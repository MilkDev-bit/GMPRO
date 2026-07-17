/**
 * @file services/payment-service/src/routes/cashPaymentRoutes.js
 * @description Ruta privada para que el recepcionista registre pagos en efectivo.
 * Protegida por API Key (middleware apiKeyAuth montado en main.js o en la ruta).
 */

'use strict';

const { Router }                   = require('express');
const { body, validationResult }   = require('express-validator');
const paymentController            = require('../controllers/paymentController');

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

// POST / (montado en /api/v1/cash-payment o /api/v1/payments/cash-payment)
router.post(
  '/',
  [
    body('usuario_id').isUUID(4).withMessage('ID de usuario (UUID v4) requerido.'),
    body('monto').isFloat({ gt: 0 }).withMessage('El monto pagado debe ser mayor a 0.'),
    body('plan_nombre').optional().trim().isLength({ max: 100 }),
    body('plan_duracion_dias').optional().isInt({ min: 1, max: 365 }).withMessage('Duración en días inválida (1-365).'),
    body('notas').optional().trim().isLength({ max: 500 }),
  ],
  validate,
  paymentController.registerCashPayment
);

module.exports = router;
