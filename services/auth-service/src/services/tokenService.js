/**
 * @file services/auth-service/src/services/tokenService.js
 * @description Generación, verificación y revocación de JWT.
 *
 * Separa la lógica de tokens del controller para mantener el SRP
 * (Single Responsibility Principle) y facilitar el testing.
 */

'use strict';

const jwt    = require('jsonwebtoken');
const crypto = require('crypto');
const env    = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:tokenService');

/**
 * Genera un access token JWT de corta duración.
 *
 * Claims incluidos:
 *   sub  → ID del usuario (estándar JWT: "subject")
 *   jti  → ID único del token (para blacklist en logout)
 *   role → Rol del usuario (para autorización en otros servicios)
 *   email → Email (evita un round-trip a la DB en cada request autenticado)
 *   iat  → Issued at (automático con jwt.sign)
 *   exp  → Expiration (automático con expiresIn)
 *
 * @param {object} user - Objeto usuario de la DB
 * @returns {string} JWT firmado
 */
function generateAccessToken(user) {
  const jti = crypto.randomUUID();  // ID único para poder revocar este token específico

  return jwt.sign(
    {
      sub:   user.id,
      email: user.email,
      role:  user.rol,
      jti,
    },
    env.JWT_SECRET,
    {
      algorithm: env.JWT_ALGORITHM,
      expiresIn: env.JWT_EXPIRES_IN,
    }
  );
}

/**
 * Genera un refresh token opaco (no JWT).
 * Al ser opaco, no contiene información en texto plano.
 * Se almacena su SHA-256 en la DB; el texto plano se envía al cliente.
 *
 * Incluye expiresAt: la EXPIRACIÓN SERVER-SIDE es la autoridad. Antes solo
 * existía el maxAge de la cookie (lado cliente), así que un hash exfiltrado de
 * la DB o una cookie robada era válido en el servidor INDEFINIDAMENTE hasta
 * rotarse. Ahora el servidor rechaza el refresh si ya venció.
 *
 * @returns {{ token: string, hash: string, expiresAt: string }}
 *   token     → texto plano (enviar al cliente en cookie HttpOnly)
 *   hash      → SHA-256 (almacenar en DB)
 *   expiresAt → ISO timestamp de expiración (almacenar en DB)
 */
function generateRefreshToken() {
  const token = crypto.randomBytes(64).toString('base64url');  // URL-safe, sin padding
  const hash  = crypto.createHash('sha256').update(token).digest('hex');
  const ttlDays   = parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10);
  const expiresAt = new Date(Date.now() + ttlDays * 24 * 60 * 60_000).toISOString();
  return { token, hash, expiresAt };
}

/**
 * Genera el token de verificación de email (UUID).
 * Se almacena directamente en la DB (no es sensible como el refresh token).
 *
 * @returns {string} UUID v4
 */
function generateVerificationToken() {
  return crypto.randomUUID();
}

/**
 * Revoca un access token agregando su JTI a la blacklist de Redis.
 * TTL = tiempo restante de vida del token (sin necesidad de guardar tokens muertos para siempre).
 *
 * @param {string} jti   - JWT ID extraído del token verificado
 * @param {number} exp   - Unix timestamp de expiración del token
 * @param {import('ioredis').Redis} redisClient
 * @returns {Promise<void>}
 */
async function revokeAccessToken(jti, exp, redisClient) {
  if (!redisClient) {
    logger.warn('Redis no disponible — token no pudo ser revocado en blacklist', { jti });
    return;
  }

  const ttlSeconds = exp - Math.floor(Date.now() / 1000);
  if (ttlSeconds <= 0) return;  // Token ya expirado, no es necesario revocar

  await redisClient.setex(`jwt:blacklist:${jti}`, ttlSeconds, '1');
  logger.info('Access token revocado en blacklist', { jti, ttlSeconds });
}

/**
 * Hashea el token de reset de contraseña para almacenamiento seguro.
 *
 * @param {string} token - Token en texto plano
 * @returns {string} SHA-256 hex
 */
function hashResetToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Genera un token de reset de contraseña seguro.
 * El texto plano se envía por email; el hash se almacena en DB.
 *
 * @returns {{ token: string, hash: string }}
 */
function generatePasswordResetToken() {
  const token = crypto.randomBytes(32).toString('hex');  // 64 caracteres hex
  const hash  = hashResetToken(token);
  return { token, hash };
}

module.exports = {
  generateAccessToken,
  generateRefreshToken,
  generateVerificationToken,
  revokeAccessToken,
  generatePasswordResetToken,
  hashResetToken,
};
