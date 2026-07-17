/**
 * @file services/access-service/src/middlewares/jwtVerify.js
 * @description Configuración de JWT específica para access-service.
 * Delega la lógica al módulo compartido en packages_shared.
 */
'use strict';

const {
  createJwtVerifyMiddleware,
  createInterServiceAuthMiddleware,
} = require('../../../../packages_shared/security/jwtVerify');

module.exports = { createJwtVerifyMiddleware, createInterServiceAuthMiddleware };
