/**
 * @file services/access-service/src/routes/internalRoutes.js
 * @description Rutas internas servicio-a-servicio (payment-service → access-service).
 * Protegidas por INTER_SERVICE_SECRET. No exponer al público.
 */

'use strict';

const { Router }                    = require('express');
const { body, validationResult }    = require('express-validator');
const internalController            = require('../controllers/internalController');
const { requireInterServiceSecret } = require('../middlewares/interServiceAuth');

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

router.post(
  '/invalidate-membership-cache',
  requireInterServiceSecret,
  [
    body('usuario_id').isUUID(4).withMessage('usuario_id (UUID v4) requerido.'),
    body('valido_hasta').optional().isISO8601().withMessage('valido_hasta debe ser ISO8601.'),
    body('estado').optional().isString().isLength({ max: 20 }),
  ],
  validate,
  internalController.invalidateMembershipCache
);

router.post(
  '/courtesy-pass',
  requireInterServiceSecret,
  [
    body('usuario_id').optional().isUUID(4).withMessage('usuario_id inválido.'),
    body('notas').optional().isString().isLength({ max: 255 }),
  ],
  validate,
  internalController.mintCourtesyPass
);

module.exports = router;
