/**
 * @file services/auth-service/src/routes/passwordRoutes.js
 * @description Rutas de gestión de contraseña.
 */

'use strict';

const { Router } = require('express');
const { body, validationResult } = require('express-validator');
const passwordController = require('../controllers/passwordController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

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

// Regla de contraseña reutilizable
const passwordRules = body('newPassword')
  .isLength({ min: 8, max: 72 }).withMessage('La contraseña debe tener entre 8 y 72 caracteres.')
  .matches(/[A-Z]/).withMessage('Debe contener al menos una mayúscula.')
  .matches(/[0-9]/).withMessage('Debe contener al menos un número.')
  .matches(/[^A-Za-z0-9]/).withMessage('Debe contener al menos un carácter especial.');

// POST /api/v1/auth/password/forgot
router.post(
  '/forgot',
  [body('email').isEmail().normalizeEmail()],
  validate,
  passwordController.forgotPassword
);

// POST /api/v1/auth/password/reset
router.post(
  '/reset',
  [
    body('token').notEmpty().isLength({ min: 64, max: 64 }).withMessage('Token inválido.'),
    passwordRules,
  ],
  validate,
  passwordController.resetPassword
);

// PUT /api/v1/auth/password/change  (JWT requerido)
router.put(
  '/change',
  createJwtVerifyMiddleware(),
  [
    body('currentPassword').notEmpty().withMessage('La contraseña actual es requerida.'),
    passwordRules,
  ],
  validate,
  passwordController.changePassword
);

module.exports = router;
