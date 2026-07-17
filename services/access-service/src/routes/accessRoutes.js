/**
 * @file services/access-service/src/routes/accessRoutes.js
 * @description Rutas unificadas para validación de acceso (torniquetes y hardware local).
 * Permite que scripts_local o el hardware llamen a /api/v1/access/validate-qr o /validate-ticket.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const qrController               = require('../controllers/qrController');
const ticketController           = require('../controllers/ticketController');
const { requireTurnstileApiKey } = require('../middlewares/turnstileAuth');

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

// POST /api/v1/access/validate-qr (o /api/v1/access/qr)
router.post(
  '/validate-qr',
  requireTurnstileApiKey,
  [
    body('token_qr').notEmpty().withMessage('El token del código QR es requerido.'),
  ],
  validate,
  qrController.verifyQr
);

router.post(
  '/qr',
  requireTurnstileApiKey,
  [
    body('token_qr').notEmpty().withMessage('El token del código QR es requerido.'),
  ],
  validate,
  qrController.verifyQr
);

// POST /api/v1/access/validate-ticket
router.post(
  '/validate-ticket',
  requireTurnstileApiKey,
  [
    body('codigo_ticket').notEmpty().withMessage('El código de ticket es requerido.'),
  ],
  validate,
  ticketController.validateTicket
);

module.exports = router;
