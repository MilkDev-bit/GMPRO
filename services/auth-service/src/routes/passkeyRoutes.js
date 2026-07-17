/**
 * @file services/auth-service/src/routes/passkeyRoutes.js
 * @description Rutas para autenticación y registro de Passkeys nativos (FIDO2/WebAuthn).
 */

'use strict';

const { Router }       = require('express');
const passkeyController = require('../controllers/passkeyController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

const router = Router();

// ── Registro de una nueva llave biométrica (Requiere estar logeado previamente) ──
router.post(
  '/register-options',
  createJwtVerifyMiddleware(),
  passkeyController.registerOptions
);

router.post(
  '/verify-register',
  createJwtVerifyMiddleware(),
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

module.exports = router;
