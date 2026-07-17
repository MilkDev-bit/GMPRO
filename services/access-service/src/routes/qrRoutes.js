/**
 * @file services/access-service/src/routes/qrRoutes.js
 * @description Rutas para generación de QR por parte de miembros y verificación por el torniquete.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const qrController               = require('../controllers/qrController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');
const { requireTurnstileApiKey }    = require('../middlewares/turnstileAuth');

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

// GET /generate (y GET /generate-qr en router raz / o alias) -> Protegido por JWT
router.get('/generate', createJwtVerifyMiddleware(), qrController.generateQr);

// POST /verify (e POST /verify-qr en router raíz) -> Protegido por API Key del torniquete
router.post(
  '/verify',
  requireTurnstileApiKey,
  [
    body('token_qr').notEmpty().withMessage('El token del código QR es requerido.'),
  ],
  validate,
  qrController.verifyQr
);

module.exports = router;
