/**
 * @file services/auth-service/src/routes/adminRoutes.js
 * @description Rutas de administración (panel). SOLO staff/admin (RBAC) y con
 * lectura de blacklist de tokens (factory recibe redisClient).
 */

'use strict';

const { Router } = require('express');
const { param, body, query, validationResult } = require('express-validator');
const adminController = require('../controllers/adminController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

// Roles autorizados al panel (mismo contrato que access-service: STAFF_ROLES).
const STAFF_ROLES = (process.env.STAFF_ROLES || 'staff,admin')
  .split(',').map((r) => r.trim().toLowerCase()).filter(Boolean);

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

  router.get(
    '/members',
    staffOnly,
    [query('search').optional().isString().isLength({ max: 80 })],
    validate,
    adminController.listMembers,
  );

  router.patch(
    '/members/:id',
    staffOnly,
    [
      param('id').isUUID(4).withMessage('id de miembro inválido.'),
      body('activo').isBoolean().withMessage('activo debe ser booleano.'),
    ],
    validate,
    adminController.setMemberActive,
  );

  return router;
};
