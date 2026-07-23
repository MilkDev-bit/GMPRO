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
const { requireAdmsDeviceAuth }    = require('../middlewares/admsDeviceAuth');

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
// Las terminales hacen peticiones con query params como ?SN=... y opcionalmente body string.
// requireAdmsDeviceAuth valida allowlist de SN + clave de push ANTES de tocar la cola
// de comandos (que contiene plantillas biométricas) o el historial de accesos.
router.get('/getrequest', requireAdmsDeviceAuth, zkAdmsController.handleGetRequest);
router.post('/getrequest', requireAdmsDeviceAuth, textBodyParser, zkAdmsController.handleGetRequest);

router.post('/devicecmd', requireAdmsDeviceAuth, textBodyParser, zkAdmsController.handleDeviceCmd);
router.get('/devicecmd', requireAdmsDeviceAuth, zkAdmsController.handleDeviceCmd);

router.post('/c/cdata', requireAdmsDeviceAuth, textBodyParser, zkAdmsController.handleCData);
router.post('/cdata', requireAdmsDeviceAuth, textBodyParser, zkAdmsController.handleCData);

router.get('/registry', requireAdmsDeviceAuth, zkAdmsController.handleRegistry);
router.post('/registry', requireAdmsDeviceAuth, textBodyParser, zkAdmsController.handleRegistry);

// ── 2. RUTAS M2M DE GESTIÓN (PARA PAYMENT-SERVICE Y PANEL ADMIN) ─────────────
// Validación de borde de /sync-user (defensa en profundidad; complementa el
// saneado ya aplicado en el sink zkAdmsService.js).
//
// Coherencia con el sink: éste depura pin y numero_tarjeta a alfanumérico
// estricto. Aquí se RECHAZA en el borde en vez de dejar que el sink los
// transforme en silencio — importante en `pin`, porque un "10-42" mutado a
// "1042" apuntaría a OTRO usuario del terminal (confusión de identidad).
//
// `checkFalsy: true` es obligatorio: el controller usa numero_tarjeta = ''
// por defecto, y sin él express-validator ejecutaría isAlphanumeric('') y
// fallaría en cada alta sin tarjeta.
const syncUserValidation = [
  body('pin')
    .notEmpty().withMessage('El PIN numérico del usuario es requerido.')
    .bail()
    .isAlphanumeric().withMessage('El PIN debe ser alfanumérico (sin espacios ni símbolos).'),
  body('nombre').optional().isString(),
  body('numero_tarjeta')
    .optional({ checkFalsy: true })
    .isAlphanumeric().withMessage('El número de tarjeta debe ser alfanumérico.'),
  body('plantilla_base64')
    .optional({ checkFalsy: true })
    .isBase64().withMessage('La plantilla biométrica debe ser Base64 válido.'),
  // usuario_id llega por el body y se guarda como metadata (UUID de Supabase).
  // Opcional: el controller no lo exige, pero si viene debe ser un UUID.
  body('usuario_id').optional({ checkFalsy: true }).isUUID().withMessage('usuario_id debe ser un UUID.'),
  // 'ALL' (broadcast a todas las terminales) o un número de serie ZK alfanumérico.
  body('serial_number')
    .optional({ checkFalsy: true })
    .matches(/^[A-Za-z0-9_-]+$/).withMessage('serial_number con formato inválido.'),
];

const deleteUserValidation = [
  body('pin')
    .notEmpty().withMessage('El PIN numérico del usuario es requerido para eliminar.')
    .bail()
    .isAlphanumeric().withMessage('El PIN debe ser alfanumérico (sin espacios ni símbolos).'),
  body('serial_number')
    .optional({ checkFalsy: true })
    .matches(/^[A-Za-z0-9_-]+$/).withMessage('serial_number con formato inválido.'),
];

router.post(
  '/sync-user',
  requireTurnstileApiKey,
  syncUserValidation,
  validate,
  zkAdmsController.syncBiometricUser
);

router.post(
  '/delete-user',
  requireTurnstileApiKey,
  deleteUserValidation,
  validate,
  zkAdmsController.deleteBiometricUser
);

module.exports = router;
