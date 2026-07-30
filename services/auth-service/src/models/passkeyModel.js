/**
 * @file services/auth-service/src/models/passkeyModel.js
 * @description Capa de acceso a datos para desafíos efímeros y credenciales Passkey (FIDO2/WebAuthn).
 * Almacena las llaves públicas criptográficas en la tabla auth_service_db.passkey_credentials.
 */

'use strict';

const { query } = require('../config/database');   // pg directo (svc_auth)
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:passkeyModel');

// Almacén en memoria de respaldo por si Redis no está disponible.
// ACOTADO + purgado periódico para evitar fuga de memoria (challenges abandonados
// que nunca se verifican quedarían colgados sin límite en un contenedor de larga vida).
const inMemoryChallenges = new Map();
const IN_MEMORY_MAX = 10_000;

// TTL por defecto de los desafíos WebAuthn: 90 s (ESTRICTAMENTE < 2 minutos).
// Un challenge de vida corta reduce la ventana de replay/fuerza bruta.
const DEFAULT_CHALLENGE_TTL_SECONDS = 90;

// Barrido periódico de expirados (cada 60 s, no mantiene vivo el proceso).
const _sweepTimer = setInterval(() => {
  const now = Date.now();
  for (const [key, val] of inMemoryChallenges) {
    if (now > val.expiresAt) inMemoryChallenges.delete(key);
  }
}, 60_000);
if (typeof _sweepTimer.unref === 'function') _sweepTimer.unref();

/**
 * Almacena el desafío criptográfico temporalmente (TTL < 2 min por defecto).
 * @param {string} key - Identificador (ej. `reg:${userId}` o `login:${challengeKey}`)
 * @param {string} challenge - Desafío aleatorio generado por @simplewebauthn/server
 * @param {object|null} redisClient - Cliente opcional de Redis
 * @param {number} ttlSeconds - Tiempo de vida en segundos (default 90 = 1.5 min)
 */
async function saveChallenge(key, challenge, redisClient = null, ttlSeconds = DEFAULT_CHALLENGE_TTL_SECONDS) {
  // Nunca permitir TTLs por encima del límite de seguridad de 2 minutos.
  const ttl = Math.min(Math.max(1, ttlSeconds), 120);

  if (redisClient) {
    try {
      await redisClient.setex(`passkey:challenge:${key}`, ttl, challenge);
      return;
    } catch (err) {
      logger.warn('Fallo al guardar desafío en Redis, usando fallback en memoria.', { error: err.message });
    }
  }

  // Cap duro: si se alcanza el máximo, evict-ar la entrada más antigua.
  if (inMemoryChallenges.size >= IN_MEMORY_MAX) {
    const oldestKey = inMemoryChallenges.keys().next().value;
    if (oldestKey !== undefined) inMemoryChallenges.delete(oldestKey);
  }

  inMemoryChallenges.set(key, {
    challenge,
    expiresAt: Date.now() + ttl * 1000,
  });
}

/**
 * Recupera y elimina (un-use de un solo uso) el desafío criptográfico para mitigar replay attacks.
 * @param {string} key
 * @param {object|null} redisClient
 * @returns {Promise<string|null>}
 */
async function getAndRemoveChallenge(key, redisClient = null) {
  if (redisClient) {
    try {
      const fullKey = `passkey:challenge:${key}`;
      const challenge = await redisClient.get(fullKey);
      if (challenge) {
        await redisClient.del(fullKey);
      }
      return challenge;
    } catch (err) {
      logger.warn('Fallo al leer desafío de Redis, verificando memoria.', { error: err.message });
    }
  }

  const stored = inMemoryChallenges.get(key);
  if (!stored) return null;

  inMemoryChallenges.delete(key);
  if (Date.now() > stored.expiresAt) {
    return null; // Expirado
  }
  return stored.challenge;
}

/**
 * Guarda una nueva credencial pública Passkey para el usuario.
 * @param {object} params
 * @param {string} params.userId
 * @param {string} params.credentialID - Base64URL string ID único del chip / authenticator
 * @param {Buffer|Uint8Array} params.publicKey - Llave pública binaria o Base64
 * @param {number} params.counter - Contador de uso del enclave biométrico
 * @param {Array<string>} params.transports - ['internal', 'hybrid', etc.]
 * @param {string} params.deviceName - Nombre o tipo de dispositivo reportado
 * @returns {Promise<object>}
 */
async function saveCredential({ userId, credentialID, publicKey, counter = 0, transports = [], deviceName = 'Dispositivo Móvil' }) {
  // publicKey se guarda como base64 en texto para portabilidad.
  const publicKeyStr = Buffer.isBuffer(publicKey) || publicKey instanceof Uint8Array
    ? Buffer.from(publicKey).toString('base64')
    : publicKey.toString();

  try {
    const { rows } = await query(
      `INSERT INTO passkey_credentials
         (user_id, credential_id, public_key, counter, transports, device_name)
       VALUES ($1,$2,$3,$4,$5,$6)
       RETURNING *`,
      [userId, credentialID, publicKeyStr, counter, transports, deviceName],
    );
    const data = rows[0];
    logger.info('Passkey registrada en DB correctamente', { id: data.id, userId });
    return data;
  } catch (error) {
    logger.error('Error al guardar credencial Passkey', { error: error.message, userId, credentialID });
    throw error;
  }
}

/**
 * Obtiene todas las credenciales Passkey activas registradas para un usuario.
 * @param {string} userId
 * @returns {Promise<Array<object>>}
 */
async function findCredentialsByUserId(userId) {
  try {
    const { rows } = await query(
      `SELECT * FROM passkey_credentials WHERE user_id = $1`,
      [userId],
    );
    return rows;
  } catch (error) {
    logger.error('Error al consultar passkeys por usuario', { error: error.message, userId });
    throw error;
  }
}

/**
 * Busca una credencial específica por su credentialID (usado al hacer login por Passkey).
 * @param {string} credentialID
 * @returns {Promise<object|null>}
 */
async function findCredentialById(credentialID) {
  // Equivale al embed PostgREST `*, usuarios(*)`: la credencial + el usuario
  // relacionado (por FK user_id) anidado como objeto `usuarios`.
  try {
    const { rows } = await query(
      `SELECT pc.*, to_jsonb(u.*) AS usuarios
       FROM passkey_credentials pc
       JOIN usuarios u ON u.id = pc.user_id
       WHERE pc.credential_id = $1
       LIMIT 1`,
      [credentialID],
    );
    return rows[0] || null;
  } catch (error) {
    logger.error('Error en findCredentialById', { error: error.message, credentialID });
    throw error;
  }
}

/**
 * Actualiza el contador de firma de la credencial tras una verificación exitosa.
 * @param {string} credentialID
 * @param {number} newCounter
 * @returns {Promise<void>}
 */
async function updateCredentialCounter(credentialID, newCounter) {
  try {
    await query(
      `UPDATE passkey_credentials SET counter = $2, ultimo_uso = $3 WHERE credential_id = $1`,
      [credentialID, newCounter, new Date().toISOString()],
    );
  } catch (error) {
    logger.error('Error al actualizar contador del Passkey', { error: error.message, credentialID });
  }
}

module.exports = {
  saveChallenge,
  getAndRemoveChallenge,
  saveCredential,
  findCredentialsByUserId,
  findCredentialById,
  updateCredentialCounter,
};
