/**
 * @file services/auth-service/src/routes/passkeyRoutes.js
 * @description Rutas para autenticación y registro de Passkeys nativos (FIDO2/WebAuthn).
 */

'use strict';

const { Router }       = require('express');
const passkeyController = require('../controllers/passkeyController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

/**
 * Factory: recibe { redisClient } para que las rutas de registro de passkey
 * (que requieren sesión activa) consulten la blacklist de tokens revocados.
 * @param {{ redisClient?: import('ioredis').Redis|null }} [deps]
 * @returns {import('express').Router}
 */
module.exports = function createPasskeyRoutes({ redisClient = null } = {}) {
  const router = Router();
  const jwtVerify = createJwtVerifyMiddleware({ redisClient });

// ── Registro de una nueva llave biométrica (Requiere estar logeado previamente) ──
router.post(
  '/register-options',
  jwtVerify,
  passkeyController.registerOptions
);

router.post(
  '/verify-register',
  jwtVerify,
  passkeyController.verifyRegister
);

// ── Inicio de sesión sin contraseña con llave biométrica (Público) ───────────────
router.post(
  '/login-options',
  passkeyController.loginOptions
);

router.post(
  '/verify-login',
  passkeyController.verifyLogin
);

  return router;
};
