/**
 * @file services/payment-service/src/routes/subscriptionRoutes.js
 * @description Rutas para consulta y gestión de suscripciones/membresías del usuario.
 */

'use strict';

const { Router }             = require('express');
const { query, validationResult } = require('express-validator');
const subscriptionController = require('../controllers/subscriptionController');

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

// GET /api/v1/subscriptions/active
router.get('/active', subscriptionController.getActiveSubscription);

// GET /api/v1/subscriptions/history
router.get(
  '/history',
  [query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('Límite inválido')],
  validate,
  subscriptionController.getSubscriptionHistory
);

// POST /api/v1/subscriptions/cancel
router.post('/cancel', subscriptionController.cancelAutoRenew);

module.exports = router;
