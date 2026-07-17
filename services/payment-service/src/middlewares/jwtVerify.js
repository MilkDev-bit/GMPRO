/**
 * @file services/payment-service/src/middlewares/jwtVerify.js
 * @description Configuración de JWT específica para payment-service.
 *
 * Nota de seguridad: El endpoint /webhooks/stripe NO usa este middleware.
 * La autenticación del webhook es via HMAC-SHA256 de Stripe (webhookController.js).
 */
'use strict';

const {
  createJwtVerifyMiddleware,
  createInterServiceAuthMiddleware,
} = require('../../../../packages_shared/security/jwtVerify');

module.exports = { createJwtVerifyMiddleware, createInterServiceAuthMiddleware };
