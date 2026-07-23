/**
 * @file services/access-service/src/routes/ticketRoutes.js
 * @description Rutas para pases/tickets de una sola visita.
 *
 * Factory: recibe { redisClient } para construir un rate limiter Redis-backed
 * a nivel de ruta (no en el mount, para no throttlear /validate del torniquete
 * con el límite estricto de emisión de /create).
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const ticketController           = require('../controllers/ticketController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');
const { createUserRateLimiter }     = require('../../../../packages_shared/security/rateLimiter');
const { requireTurnstileApiKey }    = require('../middlewares/turnstileAuth');
const env                           = require('../config/environment');

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

/**
 * @param {object} [deps]
 * @param {import('ioredis').Redis|null} [deps.redisClient]
 * @returns {import('express').Router}
 */
module.exports = function createTicketRoutes({ redisClient = null } = {}) {
  const router = Router();

  // RBAC: /create-ticket es ESTRICTAMENTE para personal interno. Los socios
  // ('miembro') usan /generate-qr (QR dinámico), no emiten pases físicos.
  // createJwtVerifyMiddleware responde 403 si el rol no está en la lista.
  const staffOnly = createJwtVerifyMiddleware({
    redisClient,
    requiredRoles: env.STAFF_ROLES, // externalizado (STAFF_ROLES)
  });

  // Anti emisión masiva: máx 30 pases/min por usuario (staff), respaldado en
  // Redis. Devuelve 429 vía el handler estándar del rateLimiter compartido.
  const ticketCreateRateLimiter = createUserRateLimiter({
    redisClient,
    max:      env.RATE_LIMIT_TICKET_MAX,
    windowMs: 60_000,
    prefix:   'rl:access:ticket:',
  });

  // POST /create (y /create-ticket en raíz) -> SOLO staff/admin.
  // ORDEN CRÍTICO: staffOnly ANTES del rate limiter. El limitador keya por
  // req.user.id, que solo existe tras verificar el JWT. Si el limitador
  // corriera primero, req.user sería undefined y caería a keying por IP
  // (varios gimnasios tras un mismo NAT compartirían cuota; evasión rotando
  // IP). El flood anónimo ya lo frena el limiter global por IP de applyGlobal.
  router.post(
    '/create',
    staffOnly,
    ticketCreateRateLimiter,
    [
      body('usuario_id').optional().isUUID(4).withMessage('UUID de usuario inválido.'),
      body('vigencia_horas').optional().isInt({ min: 1, max: 720 }).withMessage('Vigencia en horas inválida.'),
      body('notas').optional().isString().isLength({ max: 255 }),
    ],
    validate,
    ticketController.createTicket
  );

  // POST /validate (y /validate-ticket en raíz) -> API Key del torniquete.
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

  return router;
};
