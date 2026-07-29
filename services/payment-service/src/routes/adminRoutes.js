/**
 * @file services/payment-service/src/routes/adminRoutes.js
 * @description Rutas de administración financiera (panel). SOLO staff/admin.
 */

'use strict';

const { Router } = require('express');
const { param, body, query, validationResult } = require('express-validator');
const adminController = require('../controllers/adminController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

const STAFF_ROLES = (process.env.STAFF_ROLES || 'staff,admin')
  .split(',').map((r) => r.trim().toLowerCase()).filter(Boolean);

const ESTADOS = ['active', 'past_due', 'cancelled', 'trialing'];

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

module.exports = function createAdminRoutes({ redisClient = null } = {}) {
  const router = Router();
  const staffOnly = createJwtVerifyMiddleware({ redisClient, requiredRoles: STAFF_ROLES });

  router.get('/finance/summary', staffOnly, adminController.financeSummary);

  router.get(
    '/finance/series',
    staffOnly,
    [query('months').optional().isInt({ min: 1, max: 36 }).withMessage('months debe ser 1..36.')],
    validate,
    adminController.financeSeries,
  );

  router.get(
    '/subscriptions',
    staffOnly,
    [query('estado').optional().isIn(ESTADOS).withMessage('estado inválido.')],
    validate,
    adminController.listSubscriptions,
  );

  router.post(
    '/subscriptions/:id/cancel',
    staffOnly,
    [param('id').isUUID(4)],
    validate,
    adminController.cancelSubscription,
  );

  router.post(
    '/subscriptions/:id/extend',
    staffOnly,
    [
      param('id').isUUID(4),
      body('dias').isInt({ min: 1, max: 365 }).withMessage('dias debe ser 1..365.'),
    ],
    validate,
    adminController.extendSubscription,
  );

  // ── Ofertas / cupones ──────────────────────────────────────────────────────
  router.get('/offers', staffOnly, adminController.listOffers);

  router.post(
    '/offers',
    staffOnly,
    [
      body('nombre').isString().trim().notEmpty().isLength({ max: 120 }),
      body('codigo').isString().trim().matches(/^[A-Za-z0-9_-]{3,40}$/)
        .withMessage('código: 3-40 chars alfanuméricos/_/-.'),
      body('tipo').isIn(['porcentaje', 'monto_fijo', 'meses_gratis']),
      body('valor').isFloat({ min: 0 }).withMessage('valor debe ser >= 0.'),
      body('valido_desde').isISO8601().withMessage('valido_desde inválido.'),
      body('valido_hasta').isISO8601().withMessage('valido_hasta inválido.'),
      body('max_usos').optional({ nullable: true }).isInt({ min: 1 }),
    ],
    validate,
    adminController.createOffer,
  );

  router.patch(
    '/offers/:id',
    staffOnly,
    [param('id').isUUID(4), body('activa').isBoolean()],
    validate,
    adminController.setOfferActive,
  );

  return router;
};
