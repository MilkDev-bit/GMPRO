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
const { body, query, param, validationResult } = require('express-validator');
const cookieParser       = require('cookie-parser');
const authController     = require('../controllers/authController');
const sessionController  = require('../controllers/sessionController');
const createPasskeyRoutes = require('./passkeyRoutes'); // factory({ redisClient })
const { sanitizeFields } = require('../middlewares/inputSanitizer');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

/**
 * Factory: recibe { redisClient } para que las rutas protegidas (logout, me,
 * sessions) verifiquen la BLACKLIST de JTIs revocados. Sin redis, un token
 * "cerrado" en logout seguiría siendo válido hasta su expiración natural.
 * @param {{ redisClient?: import('ioredis').Redis|null }} [deps]
 * @returns {import('express').Router}
 */
module.exports = function createAuthRoutes({ redisClient = null } = {}) {
  const router = Router();

  // jwtVerify CON redis → consulta jwt:blacklist:<jti> en cada request protegida.
  const jwtVerify = createJwtVerifyMiddleware({ redisClient });

// Montar subrutas de Passkeys nativos (Apple Enclave / Android StrongBox)
router.use('/passkey', createPasskeyRoutes({ redisClient }));

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
  // Anti stored-XSS en campos de texto libre (defensa en profundidad, antes de validar).
  // NOTA: aplicar también en la futura ruta de perfil/datos médicos:
  //   sanitizeFields(['historial_clinico', 'contacto_emergencia', 'nombre', ...])
  sanitizeFields(['nombre', 'apellido_paterno', 'apellido_materno']),
  [
    body('email')
      .isEmail().withMessage('Email inválido.')
      .normalizeEmail()
      .isLength({ max: 320 }).withMessage('Email demasiado largo.'),

    // Registro PASSWORDLESS (Passkey): NO se pide contraseña.

    body('nombre')
      .trim().notEmpty().withMessage('El nombre es requerido.')
      .isLength({ max: 100 }).withMessage('Nombre demasiado largo.')
      .matches(/^[a-zA-ZÀ-ÿ\s'-]+$/).withMessage('El nombre solo puede contener letras.'),

    body('apellido_paterno')
      .optional()
      .trim()
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

    body('fecha_nacimiento')
      .optional()
      .isISO8601().withMessage('Fecha de nacimiento inválida (usa YYYY-MM-DD).'),
  ],
  validate,
  authController.register
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/otp/verify  (verifica el código de 6 dígitos del registro)
// Anti fuerza bruta: límite de intentos por código en Redis (ver controller).
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/otp/verify',
  [
    body('email').isEmail().withMessage('Email inválido.').normalizeEmail(),
    body('codigo')
      .trim()
      .isLength({ min: 6, max: 6 }).withMessage('El código debe tener 6 dígitos.')
      .isNumeric().withMessage('El código solo puede contener dígitos.'),
  ],
  validate,
  authController.verifyOtp
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
  jwtVerify,
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
  jwtVerify,
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

// ─────────────────────────────────────────────────────────────────────────────
// Gestión de sesiones / dispositivos (JWT requerido)
//   GET    /sessions             → lista sesiones activas
//   DELETE /sessions             → cierra TODAS las sesiones
//   DELETE /sessions/:familyId   → cierra un dispositivo (protegido BOLA)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/sessions',
  jwtVerify,
  sessionController.listSessions
);

router.delete(
  '/sessions',
  jwtVerify,
  sessionController.revokeAllSessions
);

router.delete(
  '/sessions/:familyId',
  jwtVerify,
  [
    param('familyId').isUUID(4).withMessage('Identificador de sesión inválido.'),
  ],
  validate,
  sessionController.revokeSession
);

  return router;
};
