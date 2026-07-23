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
    // 2.3: el acceso lo determina el PLAN (duracion_dias en tabla `planes`),
    // no el cliente. Ya NO se acepta plan_duracion_dias.
    body('plan_id').isUUID(4).withMessage('plan_id (UUID v4) requerido.'),
    // Precio dinámico: se acepta cualquier monto > 0; la diferencia contra
    // el precio de referencia se audita como variacion_precio en el ledger.
    body('monto_cobrado').isFloat({ gt: 0 }).withMessage('El monto cobrado debe ser mayor a 0.'),
    body('metodo_pago').optional().isIn(['cash', 'card_terminal', 'transfer'])
      .withMessage('metodo_pago debe ser cash, card_terminal o transfer.'),
    // 2.2: idempotencia. Se acepta por header (Idempotency-Key) o body.
    // Aquí se valida el del body si viene; el controller resuelve la fuente.
    body('idempotency_key').optional().isString().isLength({ min: 8, max: 200 })
      .withMessage('idempotency_key debe tener entre 8 y 200 caracteres.'),
    body('notas').optional().trim().isLength({ max: 500 }),
  ],
  validate,
  paymentController.registerCashPayment
);

module.exports = router;
