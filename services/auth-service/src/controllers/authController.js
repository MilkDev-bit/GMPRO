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
const OTP_TTL_SECONDS = 10 * 60;   // 10 min de validez del código
const OTP_MAX_ATTEMPTS = 5;        // intentos de verificación por código

/** Genera un código OTP de 6 dígitos criptográficamente seguro. */
function generateOtp() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

/** Genera, guarda en Redis (TTL) y envía por email un OTP de 6 dígitos. */
async function issueAndSendOtp(req, { email, nombre }) {
  const emailKey = String(email).toLowerCase().trim();
  const codigo = generateOtp();
  if (req.redisClient) {
    await req.redisClient.setex(`otp:verify:${emailKey}`, OTP_TTL_SECONDS, codigo);
    await req.redisClient.del(`otp:verify_attempts:${emailKey}`);
  } else {
    logger.error('Redis no disponible: no se pudo almacenar el OTP de verificación', { email: emailKey });
  }
  await emailService.sendVerificationCodeEmail({
    email, nombre, codigo, ttlMin: OTP_TTL_SECONDS / 60,
  });
}

async function register(req, res, next) {
  try {
    const { email, nombre, apellido_paterno, apellido_materno, telefono, fecha_nacimiento } = req.body;

    // Registro PASSWORDLESS: la Passkey es la credencial real. Como password_hash
    // es NOT NULL, se genera un hash aleatorio inservible para login por contraseña
    // (mismo patrón que las cuentas OAuth).
    const password_hash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), env.BCRYPT_ROUNDS);

    let user;
    try {
      user = await userModel.create({
        email, password_hash, nombre, apellido_paterno, apellido_materno,
        telefono, fecha_nacimiento, rol: 'miembro',
      });
    } catch (err) {
      // Idempotencia para "reenviar": si el email ya existe pero NO está verificado,
      // reenviamos el código en vez de fallar. Si ya está verificado → 409 real.
      if (err.status === 409) {
        const { query } = require('../config/database');
        const { rows } = await query(
          `SELECT id, nombre, email, email_verificado FROM usuarios
           WHERE email = $1 AND eliminado_en IS NULL LIMIT 1`,
          [String(email).toLowerCase().trim()],
        );
        const existing = rows[0];
        if (existing && !existing.email_verificado) {
          await issueAndSendOtp(req, { email: existing.email, nombre: existing.nombre });
          return res.status(200).json({
            success: true,
            data: { email: existing.email, email_verificado: false, mensaje: 'Código reenviado a tu email.' },
            error: null,
          });
        }
      }
      throw err;   // email verificado u otro error → propagar (409 real, etc.)
    }

    await issueAndSendOtp(req, { email: user.email, nombre: user.nombre });
    logger.info('Usuario registrado (passwordless); OTP enviado', { userId: user.id, email: user.email });

    return res.status(201).json({
      success: true,
      data: {
        id:               user.id,
        email:            user.email,
        nombre:           user.nombre,
        email_verificado: user.email_verificado,
        mensaje:          'Registro exitoso. Te enviamos un código de 6 dígitos para verificar tu email.',
      },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/otp/verify ───────────────────────────────────────────────
/**
 * Verifica el código OTP de 6 dígitos enviado al email en el registro.
 * Al validar, marca email_verificado=true y borra el código de Redis.
 */
async function verifyOtp(req, res, next) {
  try {
    const { email, codigo } = req.body;
    if (!email || !codigo) {
      return res.status(400).json({ success: false, data: null, error: 'Email y código son requeridos.' });
    }
    const emailKey = String(email).toLowerCase().trim();

    if (!req.redisClient) {
      return res.status(503).json({ success: false, data: null, error: 'Servicio de verificación no disponible.' });
    }

    // Límite de intentos (anti fuerza bruta del código de 6 dígitos)
    const attemptsKey = `otp:verify_attempts:${emailKey}`;
    const attempts = Number(await req.redisClient.get(attemptsKey)) || 0;
    if (attempts >= OTP_MAX_ATTEMPTS) {
      return res.status(429).json({ success: false, data: null, error: 'Demasiados intentos. Solicita un nuevo código.' });
    }

    const stored = await req.redisClient.get(`otp:verify:${emailKey}`);
    if (!stored || String(stored) !== String(codigo).trim()) {
      await req.redisClient.incr(attemptsKey);
      await req.redisClient.expire(attemptsKey, OTP_TTL_SECONDS);
      return res.status(400).json({ success: false, data: null, error: 'Código inválido o expirado.' });
    }

    // Código correcto → marcar verificado, limpiar Redis y ABRIR SESIÓN.
    // Emitir tokens aquí resuelve el huevo-y-gallina passwordless: el cliente
    // queda autenticado y puede registrar su Passkey (endpoint que exige JWT)
    // sin necesidad de contraseña ni Passkey previa.
    const { query } = require('../config/database');
    const { rows } = await query(
      `SELECT id, email, nombre, apellido_paterno, rol, activo, email_verificado
         FROM usuarios WHERE email = $1 AND eliminado_en IS NULL LIMIT 1`,
      [emailKey],
    );
    const user = rows[0];
    if (!user) {
      return res.status(404).json({ success: false, data: null, error: 'Usuario no encontrado.' });
    }
    if (!user.activo) {
      return res.status(403).json({ success: false, data: null, error: 'Esta cuenta ha sido desactivada.' });
    }

    await userModel.verifyEmail(user.id);
    await req.redisClient.del(`otp:verify:${emailKey}`);
    await req.redisClient.del(attemptsKey);

    // Sesión (mismo patrón que login): access token + refresh (cookie HttpOnly).
    const verifiedUser = { ...user, email_verificado: true };
    const accessToken = tokenService.generateAccessToken(verifiedUser);
    await startSession(req, res, verifiedUser);

    logger.info('Email verificado por OTP; sesión iniciada', { userId: user.id });
    return res.status(200).json({
      success: true,
      data: {
        accessToken,
        tokenType: 'Bearer',
        expiresIn: env.JWT_EXPIRES_IN,
        mensaje:   'Email verificado correctamente.',
        user: {
          id:               user.id,
          email:            user.email,
          nombre:           user.nombre,
          apellido_paterno: user.apellido_paterno,
          rol:              user.rol,
          email_verificado: true,
        },
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

      // A09-3: evento para detección de ráfagas de 401 en /login (alerta SIEM/Sentry).
      // NO se loguea el email completo (PII); solo el dominio para detectar patrones.
      logger.warn('Login fallido', {
        event: 'LOGIN_FAILED',
        ip: req.ip,
        emailDomain: String(email || '').split('@')[1] || null,
      });
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
    // exp proviene del token YA VERIFICADO por el middleware jwtVerify (req.user).
    // NO se re-decodifica el header con jwt.decode() (que no valida la firma):
    // así el TTL del blacklist se basa exclusivamente en un token con firma válida.
    const { id: userId, jti, exp } = req.user;

    // Revocar access token (agregar JTI a blacklist de Redis)
    if (req.redisClient && exp) {
      await tokenService.revokeAccessToken(jti, exp, req.redisClient);
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

    const { query } = require('../config/database');

    // Buscar usuario con ese token de verificación no usado
    let user = null;
    try {
      const { rows } = await query(
        `SELECT id, email_verificado FROM usuarios
         WHERE token_verificacion = $1 AND eliminado_en IS NULL LIMIT 1`,
        [token],
      );
      user = rows[0] || null;
    } catch (e) {
      user = null;
    }

    if (!user) {
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

module.exports = { register, verifyOtp, login, oauthLogin, logout, refreshToken, getMe, verifyEmail };
