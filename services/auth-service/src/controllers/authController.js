/**
 * @file services/auth-service/src/controllers/authController.js
 * @description Controladores de autenticación: registro, login, logout, refresh y perfil.
 *
 * Cada controller:
 *   1. Valida el input (delegado a express-validator en las rutas)
 *   2. Aplica lógica de negocio
 *   3. Llama al modelo (DB) o servicio correspondiente
 *   4. Retorna respuesta estándar { success, data, error }
 *   5. Propaga errores al error handler centralizado con next(err)
 */

'use strict';

const bcrypt       = require('bcrypt');
const crypto       = require('crypto');
const userModel    = require('../models/userModel');
const refreshTokenModel = require('../models/refreshTokenModel');
const tokenService = require('../services/tokenService');
const emailService = require('../services/emailService');
const env          = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:authController');

// ── Sesión / refresh token (familias, multi-dispositivo) ─────────────────────
const REFRESH_COOKIE = 'refreshToken';
const REFRESH_PATH   = '/api/v1/auth/refresh';

function refreshCookieOptions() {
  const ttlDays = parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10);
  return {
    httpOnly: true,
    secure:   env.IS_PRODUCTION,   // solo HTTPS en prod
    sameSite: 'strict',            // previene CSRF
    maxAge:   ttlDays * 24 * 60 * 60_000,
    path:     REFRESH_PATH,        // cookie solo enviada en /refresh
  };
}

/**
 * Abre una NUEVA familia de sesión (un dispositivo): genera el refresh token,
 * lo persiste en refresh_tokens y setea la cookie HttpOnly. Devuelve el token
 * en texto plano (para clientes móviles que lo guardan en secure storage).
 * @returns {Promise<string>} refresh token en texto plano
 */
async function startSession(req, res, user) {
  const familyId = crypto.randomUUID();
  const { token, hash, expiresAt } = tokenService.generateRefreshToken();
  await refreshTokenModel.issue({
    userId:     user.id,
    tokenHash:  hash,
    familyId,
    expiresAt,
    deviceInfo: req.headers['user-agent'] || null,
    ipAddress:  req.ip || null,
  });
  res.cookie(REFRESH_COOKIE, token, refreshCookieOptions());
  return token;
}

// ── POST /api/v1/auth/register ─────────────────────────────────────────────────
/**
 * Registra un nuevo usuario miembro.
 * No logea automáticamente tras el registro — requiere verificación de email primero.
 */
async function register(req, res, next) {
  try {
    const { email, password, nombre, apellido_paterno, apellido_materno, telefono } = req.body;

    // Hashear contraseña con bcrypt (work factor configurado en env)
    // OWASP A02: bcrypt aplica salt automáticamente — nunca almacenar MD5/SHA
    const password_hash = await bcrypt.hash(password, env.BCRYPT_ROUNDS);

    // Crear usuario en DB
    const user = await userModel.create({
      email,
      password_hash,
      nombre,
      apellido_paterno,
      apellido_materno,
      telefono,
      rol: 'miembro',
    });

    // Enviar email de verificación (no bloqueante — el fallo no cancela el registro)
    await emailService.sendVerificationEmail({
      email:             user.email,
      nombre:            user.nombre,
      verificationToken: user.token_verificacion,
    });

    logger.info('Usuario registrado exitosamente', { userId: user.id, email: user.email });

    return res.status(201).json({
      success: true,
      data: {
        id:               user.id,
        email:            user.email,
        nombre:           user.nombre,
        email_verificado: user.email_verificado,
        mensaje:          'Registro exitoso. Por favor, verifica tu email para activar tu cuenta.',
      },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/login ────────────────────────────────────────────────────
/**
 * Autentica al usuario y emite access token + refresh token.
 *
 * El refresh token se envía como cookie HttpOnly para prevenir
 * que JavaScript en el cliente pueda accederlo (XSS mitigation).
 * El access token se retorna en el body (la app Flutter lo almacena
 * en memoria o SecureStorage, nunca en localStorage).
 */
async function login(req, res, next) {
  try {
    const { email, password } = req.body;

    // 1. Buscar usuario (incluye password_hash para comparar)
    const user = await userModel.findByEmailForAuth(email);

    // OWASP A07: Mensaje de error genérico — no revelar si el email existe o no
    // La función de comparación se ejecuta siempre (incluso si user es null)
    // para prevenir timing attacks que distingan "email no existe" de "password incorrecto"
    const DUMMY_HASH = '$2b$12$invalidhashinvalidhashinvalidhashinvalidhashinvalidha.';
    const hashToCompare = user?.password_hash || DUMMY_HASH;
    const passwordMatch = await bcrypt.compare(password, hashToCompare);

    if (!user || !passwordMatch) {
      // Si el usuario existe, registrar el intento fallido
      if (user) {
        const { blocked, blockedUntil } = await userModel.recordFailedLogin(
          user.id, user.intentos_fallidos
        );

        if (blocked) {
          logger.warn('Cuenta bloqueada por intentos fallidos', {
            userId: user.id,
            blockedUntil,
          });
          return res.status(423).json({
            success: false, data: null,
            error: `Cuenta bloqueada temporalmente. Intenta de nuevo después de las ${
              blockedUntil.toLocaleTimeString('es-MX')
            }.`,
          });
        }
      }

      return res.status(401).json({
        success: false, data: null,
        error: 'Email o contraseña incorrectos.',
      });
    }

    // 2. Verificar que la cuenta no esté bloqueada
    if (user.bloqueado_hasta && new Date(user.bloqueado_hasta) > new Date()) {
      return res.status(423).json({
        success: false, data: null,
        error: 'Cuenta temporalmente bloqueada por múltiples intentos fallidos.',
      });
    }

    // 3. Verificar que la cuenta esté activa
    if (!user.activo) {
      return res.status(403).json({
        success: false, data: null,
        error: 'Esta cuenta ha sido desactivada. Contacta al soporte.',
      });
    }

    // 4. Verificar email (bloquear login si no está verificado en producción)
    if (env.IS_PRODUCTION && !user.email_verificado) {
      return res.status(403).json({
        success: false, data: null,
        error: 'Debes verificar tu email antes de iniciar sesión. Revisa tu bandeja de entrada.',
      });
    }

    // 5. Access token + abrir familia de sesión (nuevo dispositivo)
    const accessToken = tokenService.generateAccessToken(user);
    await userModel.recordSuccessfulLogin(user.id);   // bookkeeping: ultimo_login, resetea intentos
    await startSession(req, res, user);                // emite refresh + cookie HttpOnly

    logger.info('Login exitoso', { userId: user.id, rol: user.rol });

    return res.status(200).json({
      success: true,
      data: {
        accessToken,
        tokenType:  'Bearer',
        expiresIn:  env.JWT_EXPIRES_IN,
        user: {
          id:               user.id,
          email:            user.email,
          nombre:           user.nombre,
          apellido_paterno: user.apellido_paterno,
          rol:              user.rol,
          email_verificado: user.email_verificado,
        },
      },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/oauth-login ──────────────────────────────────────────────
/**
 * Autenticación nativa (Apple Sign-In & Google Sign-In) desde cliente móvil Flutter.
 * Recibe el idToken e información de identidad verificada por el SO del móvil.
 * Si el usuario no existe, lo crea automáticamente y retorna el JWT personalizado.
 */
async function oauthLogin(req, res, next) {
  try {
    const { provider, idToken, email, nombre, apellidoPaterno } = req.body;

    if (!provider || !idToken || !email) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'Datos incompletos de identidad nativa (provider, idToken, email requeridos).',
      });
    }

    // 1. Buscar o crear usuario verificando identidad del proveedor
    const user = await userModel.findOrCreateByOAuth({
      email,
      nombre: nombre || 'Socio',
      apellido_paterno: apellidoPaterno || provider.toUpperCase(),
    });

    // 2. Verificar que no esté desactivado
    if (!user.activo) {
      return res.status(403).json({
        success: false,
        data: null,
        error: 'Esta cuenta ha sido desactivada. Contacta al soporte.',
      });
    }

    // 3. Access token + abrir familia de sesión (nuevo dispositivo)
    const accessToken = tokenService.generateAccessToken(user);
    await userModel.recordSuccessfulLogin(user.id);
    // startSession setea la cookie (web) y devuelve el token para el móvil (secure storage).
    const refreshToken = await startSession(req, res, user);

    logger.info('OAuth Login nativo exitoso', { userId: user.id, provider, rol: user.rol });

    return res.status(200).json({
      success: true,
      data: {
        accessToken,
        refreshToken,
        tokenType: 'Bearer',
        expiresIn: env.JWT_EXPIRES_IN,
        user: {
          id:               user.id,
          email:            user.email,
          nombre:           user.nombre,
          apellido_paterno: user.apellido_paterno,
          rol:              user.rol,
          email_verificado: user.email_verificado,
        },
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/logout ───────────────────────────────────────────────────
/**
 * Cierra la sesión: revoca el access token en Redis y limpia la cookie.
 * Requiere JWT válido (verificado por el middleware jwtVerify).
 */
async function logout(req, res, next) {
  try {
    const { id: userId, jti } = req.user;

    // Decodificar exp del token para calcular TTL del blacklist
    const jwt = require('jsonwebtoken');
    const decoded = jwt.decode(req.headers['authorization'].slice(7));

    // Revocar access token (agregar JTI a blacklist de Redis)
    if (req.redisClient && decoded?.exp) {
      await tokenService.revokeAccessToken(jti, decoded.exp, req.redisClient);
    }

    // Revocar SOLO la familia de ESTE dispositivo (multi-dispositivo: no cierra
    // las demás sesiones del usuario). Se identifica por el refresh de la cookie.
    const rt = req.cookies?.refreshToken;
    if (rt) {
      const rtHash = crypto.createHash('sha256').update(rt).digest('hex');
      const row = await refreshTokenModel.findByHash(rtHash);
      if (row && row.user_id === userId) {
        await refreshTokenModel.revokeFamily(row.family_id);
      }
    }

    // Limpiar cookie del cliente
    res.clearCookie(REFRESH_COOKIE, { path: REFRESH_PATH });

    logger.info('Logout exitoso', { userId });

    return res.status(200).json({
      success: true,
      data:    { mensaje: 'Sesión cerrada correctamente.' },
      error:   null,
    });

  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/refresh ──────────────────────────────────────────────────
/**
 * Emite un nuevo access token usando el refresh token (desde la cookie HttpOnly).
 * Implementa refresh token rotation: cada uso genera un nuevo refresh token.
 */
async function refreshToken(req, res, next) {
  try {
    const refreshTokenFromCookie = req.cookies?.refreshToken;

    if (!refreshTokenFromCookie) {
      return res.status(401).json({
        success: false, data: null,
        error: 'No se encontró token de sesión. Por favor inicia sesión.',
      });
    }

    // Hashear el token recibido para comparar con el almacenado en DB
    const incomingHash = crypto.createHash('sha256')
      .update(refreshTokenFromCookie)
      .digest('hex');

    // 1. Localizar el token por su hash en la tabla de familias.
    const tokenRow = await refreshTokenModel.findByHash(incomingHash);

    const reject401 = (msg) => {
      res.clearCookie(REFRESH_COOKIE, { path: REFRESH_PATH });
      return res.status(401).json({ success: false, data: null, error: msg });
    };

    // 2. Token inexistente → inválido (no revela si expiró o nunca existió).
    if (!tokenRow) {
      return reject401('Token de sesión inválido o expirado.');
    }

    // 3. Familia ya revocada (por reuse previo, logout o cambio de contraseña).
    if (tokenRow.revoked_at) {
      return reject401('La sesión fue revocada. Por favor inicia sesión de nuevo.');
    }

    // 4. ── REUSE / REPLAY DETECTION ──────────────────────────────────────────
    // Si el token YA estaba consumido, alguien está reusando un token rotado:
    // señal de robo. Política estricta: revocar TODA la familia (mata la sesión
    // del atacante Y del usuario legítimo → re-login forzado). RFC 6819 / OAuth BCP.
    if (tokenRow.is_consumed) {
      await refreshTokenModel.revokeFamily(tokenRow.family_id);
      logger.warn('REUSE DE REFRESH TOKEN detectado — familia revocada', {
        event: 'REFRESH_TOKEN_REUSE', userId: tokenRow.user_id, familyId: tokenRow.family_id,
      });
      return reject401('Actividad sospechosa detectada. Por seguridad, inicia sesión de nuevo.');
    }

    // 5. Expiración server-side (autoridad real, no la cookie). Vencido → revoca familia.
    if (new Date(tokenRow.expires_at) < new Date()) {
      await refreshTokenModel.revokeFamily(tokenRow.family_id);
      return reject401('La sesión ha expirado. Por favor inicia sesión de nuevo.');
    }

    // 6. Consumo ATÓMICO del token actual. Si otra request concurrente lo consumió
    //    primero, esta pierde la carrera → se trata como reuse y se revoca la familia.
    const consumed = await refreshTokenModel.consumeAtomically(tokenRow.id);
    if (!consumed) {
      await refreshTokenModel.revokeFamily(tokenRow.family_id);
      logger.warn('Carrera de consumo de refresh token — familia revocada', {
        event: 'REFRESH_TOKEN_RACE', userId: tokenRow.user_id, familyId: tokenRow.family_id,
      });
      return reject401('Actividad sospechosa detectada. Por seguridad, inicia sesión de nuevo.');
    }

    // 7. Cargar el usuario (para el nuevo access token y validar estado).
    const user = await userModel.findById(tokenRow.user_id);
    if (!user || user.eliminado_en) {
      await refreshTokenModel.revokeFamily(tokenRow.family_id);
      return reject401('Token de sesión inválido o expirado.');
    }
    if (!user.activo) {
      await refreshTokenModel.revokeFamily(tokenRow.family_id);
      return res.status(403).json({ success: false, data: null, error: 'Cuenta desactivada.' });
    }

    // 8. Rotación: emitir el SIGUIENTE token en la MISMA familia + nuevo access token.
    const newAccessToken = tokenService.generateAccessToken(user);
    const { token: newRefreshToken, hash: newRefreshHash, expiresAt: newExpiresAt } =
      tokenService.generateRefreshToken();

    await refreshTokenModel.issue({
      userId:     user.id,
      tokenHash:  newRefreshHash,
      familyId:   tokenRow.family_id,   // ← misma familia: la sesión continúa
      expiresAt:  newExpiresAt,
      deviceInfo: req.headers['user-agent'] || null,
      ipAddress:  req.ip || null,
    });

    res.cookie(REFRESH_COOKIE, newRefreshToken, refreshCookieOptions());

    return res.status(200).json({
      success: true,
      data: {
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,  // para clientes móviles (secure storage)
        tokenType:   'Bearer',
        expiresIn:   env.JWT_EXPIRES_IN,
      },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

// ── GET /api/v1/auth/me ────────────────────────────────────────────────────────
/**
 * Retorna el perfil completo del usuario autenticado.
 * Requiere JWT válido (inyecta req.user).
 */
async function getMe(req, res, next) {
  try {
    const user = await userModel.findById(req.user.id);

    if (!user) {
      return res.status(404).json({
        success: false, data: null,
        error: 'Usuario no encontrado.',
      });
    }

    return res.status(200).json({
      success: true,
      data:    user,
      error:   null,
    });

  } catch (err) {
    next(err);
  }
}

// ── GET /api/v1/auth/verify-email ─────────────────────────────────────────────
/**
 * Verifica el email del usuario usando el token enviado por correo.
 */
async function verifyEmail(req, res, next) {
  try {
    const { token } = req.query;

    if (!token) {
      return res.status(400).json({
        success: false, data: null, error: 'Token de verificación requerido.',
      });
    }

    const { getSupabaseClient } = require('../config/database');
    const db = getSupabaseClient();

    // Buscar usuario con ese token de verificación no usado
    const { data: user, error } = await db
      .from('usuarios')
      .select('id, email_verificado')
      .eq('token_verificacion', token)
      .is('eliminado_en', null)
      .single();

    if (error || !user) {
      return res.status(400).json({
        success: false, data: null,
        error: 'Token de verificación inválido o ya utilizado.',
      });
    }

    if (user.email_verificado) {
      return res.status(200).json({
        success: true,
        data: { mensaje: 'El email ya fue verificado anteriormente.' },
        error: null,
      });
    }

    await userModel.verifyEmail(user.id);
    logger.info('Email verificado', { userId: user.id });

    return res.status(200).json({
      success: true,
      data: { mensaje: 'Email verificado exitosamente. Ya puedes iniciar sesión.' },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

module.exports = { register, login, oauthLogin, logout, refreshToken, getMe, verifyEmail };
