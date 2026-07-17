/**
 * @file services/payment-service/src/routes/webhookRoutes.js
 * @description Rutas para recepción de webhooks externos (ej. Stripe).
 *
 * ⚠️ ATENCIÓN: El body de POST /stripe es procesado como raw Buffer
 * por el middleware de express.raw() montado en main.js ANTES del parser JSON.
 * NUNCA aplicar parsers ni middlewares que modifiquen el body aquí.
 */

'use strict';

const { Router }          = require('express');
const webhookController   = require('../controllers/webhookController');

const router = Router();

// POST /api/v1/webhooks/stripe
router.post('/stripe', webhookController.handleStripeWebhook);

module.exports = router;
