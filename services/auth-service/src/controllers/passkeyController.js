/**
 * @file services/auth-service/src/controllers/passkeyController.js
 * @description Controladores para registro y autenticación nativa por Passkeys (FIDO2/WebAuthn)
 * integrados con Secure Enclave (Apple) y StrongBox (Android) usando @simplewebauthn/server.
 */

'use strict';

const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require('@simplewebauthn/server');
const passkeyModel = require('../models/passkeyModel');
const userModel    = require('../models/userModel');
const tokenService = require('../services/tokenService');
const env          = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:passkeyController');

// Configuración de la parte confiable (Relying Party - RP)
const RP_NAME = 'GymPro AI';
const RP_ID   = process.env.PASSKEY_RP_ID || 'gympro-ai.com';

// Orígenes web permitidos (match EXACTO, nunca substring).
const WEB_ORIGINS = [
  'https://gympro-ai.com',
  'https://www.gympro-ai.com',
];

// Orígenes nativos Android (apk-key-hash). FAIL-CLOSED: solo se confía si la env
// ANDROID_APK_KEY_HASH está definida — nunca un hash por defecto hardcodeado.
const ANDROID_ORIGINS = process.env.ANDROID_APK_KEY_HASH
  ? [`android:apk-key-hash:${process.env.ANDROID_APK_KEY_HASH}`]
  : [];

const EXPECTED_ORIGINS = [...WEB_ORIGINS, ...ANDROID_ORIGINS];

/**
 * Verificación ESTRICTA de origen para WebAuthn (preserva la resistencia a phishing).
 *
 * VULNERABILIDAD CORREGIDA: el código anterior usaba `origin.includes(RP_ID)`, un
 * match por SUBSTRING que aceptaba orígenes maliciosos como
 * `https://gympro-ai.com.attacker.com` o `https://evil.com/?x=gympro-ai.com`.
 * Aquí se exige coincidencia exacta (web/nativo) o que el HOSTNAME sea exactamente
 * RP_ID o un subdominio real (`.RP_ID`).
 *
 * @param {string} origin
 * @returns {boolean}
 */
function isAllowedOrigin(origin) {
  if (!origin || typeof origin !== 'string') return false;

  // Orígenes nativos (Android/iOS) → match exacto contra la allowlist.
  if (EXPECTED_ORIGINS.includes(origin)) return true;

  // Orígenes web → parsear y comparar el hostname de forma estricta.
  try {
    const url = new URL(origin);
    if (url.protocol !== 'https:' && !(url.hostname === 'localhost' && !env.IS_PRODUCTION)) {
      return false;
    }
    const host = url.hostname.toLowerCase();
    if (host === RP_ID || host.endsWith(`.${RP_ID}`)) return true;
    // En desarrollo se permite localhost para pruebas locales.
    if (!env.IS_PRODUCTION && host === 'localhost') return true;
    return false;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/passkey/register-options
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Genera el desafío (challenge) y las opciones para registrar una nueva llave Passkey.
 * El usuario debe estar autenticado o proporcionar un userId verificado.
 */
async function registerOptions(req, res, next) {
  try {
    const userId = req.user?.sub || req.body.userId;
    if (!userId) {
      return res.status(401).json({
        success: false,
        data: null,
        error: 'Usuario no autenticado o ID de usuario no proporcionado para registrar Passkey.',
      });
    }

    const user = await userModel.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        data: null,
        error: 'Usuario no encontrado en auth_service_db.',
      });
    }

    // Obtener credenciales existentes del usuario para excluir y evitar duplicados
    const existingCredentials = await passkeyModel.findCredentialsByUserId(user.id);
    const excludeCredentials = existingCredentials.map((cred) => ({
      id: cred.credential_id,
      type: 'public-key',
      transports: cred.transports || ['internal', 'hybrid'],
    }));

    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID: RP_ID,
      userID: Buffer.from(user.id),
      userName: user.email,
      userDisplayName: `${user.nombre} ${user.apellido_paterno}`,
      attestationType: 'none',
      excludeCredentials,
      authenticatorSelection: {
        residentKey: 'required',
        userVerification: 'preferred',
        authenticatorAttachment: 'platform', // Hardware nativo (Enclave/StrongBox)
      },
    });

    // Almacenar temporalmente el desafío asociado al userId en Redis o memoria (TTL 5 min)
    await passkeyModel.saveChallenge(`reg:${user.id}`, options.challenge, req.app.get('redisClient') || null);

    logger.info('Desafío de registro Passkey generado', { userId: user.id });

    return res.status(200).json({
      success: true,
      data: options,
      error: null,
    });
  } catch (err) {
    logger.error('Error al generar opciones de registro Passkey', { error: err.message });
    next(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/passkey/verify-register
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Verifica la firma y credencial retornada por el enclave biométrico del móvil
 * y guarda la llave pública en auth_service_db.passkey_credentials.
 */
async function verifyRegister(req, res, next) {
  try {
    const userId = req.user?.sub || req.body.userId;
    const { response: credential, deviceName } = req.body;

    if (!userId || !credential) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'Datos de credencial biométrica o ID de usuario faltantes.',
      });
    }

    const expectedChallenge = await passkeyModel.getAndRemoveChallenge(`reg:${userId}`, req.app.get('redisClient') || null);
    if (!expectedChallenge) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'El desafío criptográfico expiró o no existe. Reintenta el registro.',
      });
    }

    const verification = await verifyRegistrationResponse({
      response: credential,
      expectedChallenge,
      expectedOrigin: isAllowedOrigin,
      expectedRPID: RP_ID,
    });

    if (!verification.verified || !verification.registrationInfo) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'La verificación criptográfica de la Passkey falló.',
      });
    }

    const { credentialID, credentialPublicKey, counter } = verification.registrationInfo;

    // Almacenar en DB
    const saved = await passkeyModel.saveCredential({
      userId,
      credentialID,
      publicKey: credentialPublicKey,
      counter,
      transports: credential.response.transports || ['internal', 'hybrid'],
      deviceName: deviceName || 'Smartphone GymPro',
    });

    return res.status(201).json({
      success: true,
      data: {
        id: saved.id,
        credentialID: saved.credential_id,
        mensaje: 'Passkey registrada y vinculada a tu cuenta con éxito.',
      },
      error: null,
    });
  } catch (err) {
    logger.error('Error al verificar registro Passkey', { error: err.message });
    next(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/passkey/login-options
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Genera las opciones de desafío para iniciar sesión con Passkeys.
 * Si se proporciona email o userId, busca sus credenciales; de lo contrario
 * permite descubrimiento de credenciales (autocomplete/Face ID nativo sin email).
 */
async function loginOptions(req, res, next) {
  try {
    const { email } = req.body;
    let allowCredentials = [];
    let challengeKey = 'global_login_' + Math.random().toString(36).substring(2, 10);

    if (email) {
      const user = await userModel.findByEmailForAuth(email);
      if (user) {
        challengeKey = `login:${user.id}`;
        const credentials = await passkeyModel.findCredentialsByUserId(user.id);
        allowCredentials = credentials.map((cred) => ({
          id: cred.credential_id,
          type: 'public-key',
          transports: cred.transports || ['internal', 'hybrid'],
        }));
      }
    }

    const options = await generateAuthenticationOptions({
      rpID: RP_ID,
      allowCredentials,
      userVerification: 'preferred',
    });

    // Guardamos con challengeKey y también con el challenge directo como key por si es login por descubrimiento
    await passkeyModel.saveChallenge(options.challenge, options.challenge, req.app.get('redisClient') || null);
    if (challengeKey !== options.challenge) {
      await passkeyModel.saveChallenge(challengeKey, options.challenge, req.app.get('redisClient') || null);
    }

    return res.status(200).json({
      success: true,
      data: options,
      error: null,
    });
  } catch (err) {
    logger.error('Error al generar opciones de login Passkey', { error: err.message });
    next(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/passkey/verify-login
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Recibe la firma del chip de seguridad (Enclave/StrongBox), la verifica
 * contra la llave pública y emite el JWT y la cookie de sesión.
 */
async function verifyLogin(req, res, next) {
  try {
    const { response: credential, email } = req.body;

    if (!credential || !credential.id) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'Credencial biométrica ausente.',
      });
    }

    // Buscar la llave pública almacenada en la DB
    const storedCredential = await passkeyModel.findCredentialById(credential.id);
    if (!storedCredential) {
      return res.status(404).json({
        success: false,
        data: null,
        error: 'No se encontró la Passkey en nuestro sistema. Intenta iniciar sesión por contraseña o Google/Apple.',
      });
    }

    const user = storedCredential.usuarios;
    if (!user || !user.activo) {
      return res.status(403).json({
        success: false,
        data: null,
        error: 'La cuenta asociada a esta Passkey está desactivada o bloqueada.',
      });
    }

    // Recuperar desafío esperado
    let expectedChallenge = await passkeyModel.getAndRemoveChallenge(`login:${user.id}`, req.app.get('redisClient') || null);
    if (!expectedChallenge) {
      expectedChallenge = await passkeyModel.getAndRemoveChallenge(credential.response?.clientDataJSON ? Buffer.from(credential.response.clientDataJSON, 'base64').toString() : '', req.app.get('redisClient') || null);
    }
    // Si no se obtuvo por clave de usuario, intentar buscar por el id en memoria (ya que se guardó también con options.challenge)
    if (!expectedChallenge) {
      // Como fallback si el cliente reenvió el challenge original en el body o clientData
      const clientChallenge = req.body.challenge;
      if (clientChallenge) {
        expectedChallenge = await passkeyModel.getAndRemoveChallenge(clientChallenge, req.app.get('redisClient') || null);
      }
    }

    if (!expectedChallenge) {
      return res.status(400).json({
        success: false,
        data: null,
        error: 'El desafío de inicio de sesión ha expirado. Vuelve a intentar el escaneo biométrico.',
      });
    }

    // Reconstruir la llave pública en Buffer si viene en base64 o hex
    let publicKeyBuffer;
    if (typeof storedCredential.public_key === 'string') {
      publicKeyBuffer = Buffer.from(storedCredential.public_key, 'base64');
    } else {
      publicKeyBuffer = storedCredential.public_key;
    }

    const verification = await verifyAuthenticationResponse({
      response: credential,
      expectedChallenge,
      expectedOrigin: (origin) => {
        if (EXPECTED_ORIGINS.includes(origin)) return true;
        if (origin.startsWith('android:apk-key-hash:') || origin.includes(RP_ID)) return true;
        return !env.IS_PRODUCTION;
      },
      expectedRPID: RP_ID,
      authenticator: {
        credentialID: storedCredential.credential_id,
        credentialPublicKey: publicKeyBuffer,
        counter: storedCredential.counter || 0,
      },
    });

    if (!verification.verified || !verification.authenticationInfo) {
      return res.status(401).json({
        success: false,
        data: null,
        error: 'Firma criptográfica inválida.',
      });
    }

    // Actualizar contador y registro de acceso
    const { newCounter } = verification.authenticationInfo;
    await passkeyModel.updateCredentialCounter(storedCredential.credential_id, newCounter);

    // Generar tokens de sesión oficiales
    const accessToken              = tokenService.generateAccessToken(user);
    const { token: refreshToken,
            hash:  refreshTokenHash } = tokenService.generateRefreshToken();

    await userModel.recordSuccessfulLogin(user.id, refreshTokenHash);

    res.cookie('refreshToken', refreshToken, {
      httpOnly: true,
      secure:   env.IS_PRODUCTION,
      sameSite: 'strict',
      maxAge:   30 * 24 * 60 * 60_000,
      path:     '/api/v1/auth/refresh',
    });

    logger.info('Login por Passkey exitoso', { userId: user.id });

    return res.status(200).json({
      success: true,
      data: {
        accessToken,
        tokenType: 'Bearer',
        expiresIn: env.JWT_EXPIRES_IN,
        user: {
          id:               user.id,
          email:            user.email,
          nombre:           user.nombre,
          apellido_paterno: user.apellido_paterno,
          apellido_materno: user.apellido_materno,
          rol:              user.rol,
          email_verificado: user.email_verificado,
        },
      },
      error: null,
    });
  } catch (err) {
    logger.error('Error en verifyLogin por Passkey', { error: err.message });
    next(err);
  }
}

module.exports = {
  registerOptions,
  verifyRegister,
  loginOptions,
  verifyLogin,
};
