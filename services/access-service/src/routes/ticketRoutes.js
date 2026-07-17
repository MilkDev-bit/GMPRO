/**
 * @file services/access-service/src/routes/ticketRoutes.js
 * @description Rutas para pases/tickets de una sola visita.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const ticketController           = require('../controllers/ticketController');
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

// POST /create (y /create-ticket en raíz) -> Requiere JWT o ser invocado en recepción
router.post(
  '/create',
  createJwtVerifyMiddleware(),
  [
    body('usuario_id').optional().isUUID(4).withMessage('UUID de usuario inválido.'),
    body('vigencia_horas').optional().isInt({ min: 1, max: 720 }).withMessage('Vigencia en horas inválida.'),
    body('notas').optional().isString().isLength({ max: 255 }),
  ],
  validate,
  ticketController.createTicket
);

// POST /validate (y /validate-ticket en raíz) -> Protegido por API Key del torniquete
router.post(
  '/validate',
  requireTurnstileApiKey,
  [
    body('codigo_ticket').optional().notEmpty().withMessage('El código de ticket es requerido.'),
    body('token').optional().notEmpty().withMessage('El token es requerido.'),
  ],
  validate,
  ticketController.validateTicket
);

module.exports = router;
