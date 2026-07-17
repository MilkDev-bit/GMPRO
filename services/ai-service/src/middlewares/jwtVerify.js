/**
 * @file services/ai-service/src/middlewares/jwtVerify.js
 * @description Configuración de JWT específica para ai-service.
 * Solo rutas de usuario: /chat y /recommendations. No hay endpoints M2M de entrada.
 */
'use strict';

const {
  createJwtVerifyMiddleware,
} = require('../../../../packages_shared/security/jwtVerify');

// El ai-service NO expone endpoints M2M (solo los consume hacia fitness-service)
module.exports = { createJwtVerifyMiddleware };
