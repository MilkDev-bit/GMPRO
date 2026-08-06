/**
 * @file services/payment-service/src/routes/paymentRoutes.js
 * @description Rutas para operaciones de pago online (Stripe Checkout) y descargas de comprobantes.
 */

'use strict';

const { Router }                   = require('express');
const { body, param, validationResult } = require('express-validator');
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

// POST /api/v1/payments/create-checkout-session
router.post(
  '/create-checkout-session',
  [
    // El precio ya NO lo dicta el cliente: se envía un `plan` y el servidor lo
    // mapea a STRIPE_PRICE_ID_* (ver createCheckoutSession).
    body('plan').optional().isIn(['mensual', 'trimestral', 'anual'])
      .withMessage('Plan inválido (usa "mensual", "trimestral" o "anual").'),
    // success/cancel URL las FIJA el servidor (ver createCheckoutSession); no se
    // validan aquí — el saneador escapaba las del cliente y rompía isURL.
    body('offerCode').optional({ nullable: true }).isString().trim()
      .matches(/^[A-Za-z0-9_-]{3,40}$/).withMessage('Código promocional inválido.'),
  ],
  validate,
  paymentController.createCheckoutSession
);

// GET /api/v1/payments/:id/receipt
router.get(
  '/:id/receipt',
  [
    param('id').isUUID().withMessage('ID de suscripción/pago inválido.'),
  ],
  validate,
  paymentController.getReceiptPdf
);

module.exports = router;
