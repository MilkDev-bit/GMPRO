/**
 * @file services/auth-service/src/routes/authRoutes.js
 * @description Rutas de autenticación con validación de entrada (express-validator).
 *
 * La validación aquí es la PRIMERA capa de defensa en el controller.
 * Los datos ya pasaron por inputSanitizer.js (XSS/injection),
 * aquí validamos tipos, formatos y reglas de negocio.
 */

'use strict';

const { Router }         = require('express');
const { body, query, validationResult } = require('express-validator');
const cookieParser       = require('cookie-parser');
const authController     = require('../controllers/authController');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

const router = Router();

// Cookie parser para leer el refresh token de la cookie HttpOnly
router.use(cookieParser());

// ── Middleware de resultado de validación ──────────────────────────────────────
// Extrae los errores de express-validator y retorna 422 si hay alguno.
function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false,
      data:    null,
      error:   errors.array().map((e) => `${e.path}: ${e.msg}`).join(' | '),
    });
  }
  next();
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/register
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/register',
  [
    body('email')
      .isEmail().withMessage('Email inválido.')
      .normalizeEmail()
      .isLength({ max: 320 }).withMessage('Email demasiado largo.'),

    body('password')
      .isLength({ min: 8, max: 72 }).withMessage('La contraseña debe tener entre 8 y 72 caracteres.')
      .matches(/[A-Z]/).withMessage('La contraseña debe contener al menos una mayúscula.')
      .matches(/[0-9]/).withMessage('La contraseña debe contener al menos un número.')
      .matches(/[^A-Za-z0-9]/).withMessage('La contraseña debe contener al menos un carácter especial.'),

    body('nombre')
      .trim().notEmpty().withMessage('El nombre es requerido.')
      .isLength({ max: 100 }).withMessage('Nombre demasiado largo.')
      .matches(/^[a-zA-ZÀ-ÿ\s'-]+$/).withMessage('El nombre solo puede contener letras.'),

    body('apellido_paterno')
      .trim().notEmpty().withMessage('El apellido paterno es requerido.')
      .isLength({ max: 100 })
      .matches(/^[a-zA-ZÀ-ÿ\s'-]+$/),

    body('apellido_materno')
      .optional()
      .trim()
      .isLength({ max: 100 })
      .matches(/^[a-zA-ZÀ-ÿ\s'-]+$/),

    body('telefono')
      .optional()
      .isMobilePhone('es-MX').withMessage('Número de teléfono mexicano inválido.'),
  ],
  validate,
  authController.register
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/login
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/login',
  [
    body('email')
      .isEmail().withMessage('Email inválido.')
      .normalizeEmail(),

    body('password')
      .notEmpty().withMessage('La contraseña es requerida.')
      .isLength({ max: 200 }).withMessage('Contraseña demasiado larga.'),
  ],
  validate,
  authController.login
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/oauth-login  (Login Nativo Apple / Google desde Móvil)
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/oauth-login',
  [
    body('provider').isIn(['google', 'apple']).withMessage('Proveedor inválido (debe ser google o apple).'),
    body('idToken').notEmpty().withMessage('El idToken es requerido.'),
    body('email').isEmail().withMessage('Email inválido.').normalizeEmail(),
  ],
  validate,
  authController.oauthLogin
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/logout  (JWT requerido)
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/logout',
  createJwtVerifyMiddleware(),
  authController.logout
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/refresh  (cookie HttpOnly requerida)
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/refresh',
  authController.refreshToken   // Sin JWT — usa cookie; la validación es interna
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/me  (JWT requerido)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/me',
  createJwtVerifyMiddleware(),
  authController.getMe
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/verify-email
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/verify-email',
  [
    query('token').isUUID(4).withMessage('Token de verificación inválido.'),
  ],
  validate,
  authController.verifyEmail
);

module.exports = router;
