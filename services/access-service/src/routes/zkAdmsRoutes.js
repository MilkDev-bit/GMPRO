/**
 * @file services/access-service/src/routes/zkAdmsRoutes.js
 * @description Rutas para el protocolo ZKTeco ADMS (Push HTTP / iClock)
 * y endpoints de gestión de rostros (SpeedFace-V5L).
 */

'use strict';

const express = require('express');
const { body, validationResult }   = require('express-validator');
const zkAdmsController             = require('../controllers/zkAdmsController');
const { requireTurnstileApiKey }   = require('../middlewares/turnstileAuth');

const router = express.Router();

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

// Middleware para procesar cuerpos en texto plano o form-data enviados por terminales ZKTeco
const textBodyParser = express.text({ type: '*/*', limit: '2mb' });

// ── 1. RUTAS ADMS ICLOCK (CONSULTADAS POR LA TERMINAL SPEEDFACE-V5L) ─────────
// Las terminales hacen peticiones con query params como ?SN=... y opcionalmente body string
router.get('/getrequest', zkAdmsController.handleGetRequest);
router.post('/getrequest', textBodyParser, zkAdmsController.handleGetRequest);

router.post('/devicecmd', textBodyParser, zkAdmsController.handleDeviceCmd);
router.get('/devicecmd', zkAdmsController.handleDeviceCmd);

router.post('/c/cdata', textBodyParser, zkAdmsController.handleCData);
router.post('/cdata', textBodyParser, zkAdmsController.handleCData);

router.get('/registry', zkAdmsController.handleRegistry);
router.post('/registry', textBodyParser, zkAdmsController.handleRegistry);

// ── 2. RUTAS M2M DE GESTIÓN (PARA PAYMENT-SERVICE Y PANEL ADMIN) ─────────────
router.post(
  '/sync-user',
  requireTurnstileApiKey,
  [
    body('pin').notEmpty().withMessage('El PIN numérico del usuario es requerido.'),
    body('nombre').optional().isString(),
  ],
  validate,
  zkAdmsController.syncBiometricUser
);

router.post(
  '/delete-user',
  requireTurnstileApiKey,
  [
    body('pin').notEmpty().withMessage('El PIN numérico del usuario es requerido para eliminar.'),
  ],
  validate,
  zkAdmsController.deleteBiometricUser
);

module.exports = router;
