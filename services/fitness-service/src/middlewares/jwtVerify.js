/**
 * @file services/fitness-service/src/middlewares/jwtVerify.js
 * @description Configuración de JWT específica para fitness-service.
 * El endpoint /internal/user-context usa M2M (interServiceAuth), no JWT de usuario.
 */
'use strict';

const {
  createJwtVerifyMiddleware,
  createInterServiceAuthMiddleware,
} = require('../../../../packages_shared/security/jwtVerify');

module.exports = { createJwtVerifyMiddleware, createInterServiceAuthMiddleware };
