/**
 * @file services/auth-service/src/models/refreshTokenModel.js
 * @description Capa de datos de refresh tokens con FAMILIAS y REUSE DETECTION.
 * Mínimo privilegio (CLD-1): pg con rol svc_auth, SQL parametrizado.
 *
 * Modelo: cada login abre una FAMILIA (family_id); cada /refresh consume el token
 * actual (is_consumed=true, atómico) y emite el siguiente en la misma familia.
 * Reuse de un token ya consumido → el controlador revoca la familia entera.
 * Solo se almacena el SHA-256 del token.
 */

'use strict';

const { query } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:refreshTokenModel');

/** Emite (persiste) un nuevo refresh token dentro de una familia. */
async function issue({ userId, tokenHash, familyId, expiresAt, deviceInfo = null, ipAddress = null }) {
  const { rows } = await query(
    `INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at, device_info, ip_address)
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING id, family_id, expires_at`,
    [
      userId, familyId, tokenHash, expiresAt,
      deviceInfo ? String(deviceInfo).slice(0, 255) : null,
      ipAddress ? String(ipAddress).slice(0, 64) : null,
    ],
  );
  return rows[0];
}

/** Busca un token por su hash. @returns {Promise<object|null>} */
async function findByHash(tokenHash) {
  const { rows } = await query(
    `SELECT id, user_id, family_id, is_consumed, expires_at, revoked_at
     FROM refresh_tokens WHERE token_hash = $1 LIMIT 1`,
    [tokenHash],
  );
  return rows[0] || null;
}

/**
 * Consume un token ATÓMICAMENTE: is_consumed=true SOLO si estaba sin consumir y
 * sin revocar. Concurrencia: solo una request lo consigue (la otra → 0 filas → REUSE).
 * @returns {Promise<boolean>} true si ESTA llamada lo consumió.
 */
async function consumeAtomically(id) {
  const { rows } = await query(
    `UPDATE refresh_tokens SET is_consumed = true, consumed_at = $2
     WHERE id = $1 AND is_consumed = false AND revoked_at IS NULL
     RETURNING id`,
    [id, new Date().toISOString()],
  );
  return rows.length === 1;
}

/** Revoca TODA una familia (reuse o logout de un dispositivo). @returns {Promise<number>} */
async function revokeFamily(familyId) {
  const { rows } = await query(
    `UPDATE refresh_tokens SET revoked_at = $2
     WHERE family_id = $1 AND revoked_at IS NULL RETURNING id`,
    [familyId, new Date().toISOString()],
  );
  const count = rows.length;
  if (count > 0) logger.warn('Familia de refresh tokens revocada', { familyId, count });
  return count;
}

/** Revoca TODAS las familias de un usuario. @returns {Promise<number>} */
async function revokeAllForUser(userId) {
  const { rows } = await query(
    `UPDATE refresh_tokens SET revoked_at = $2
     WHERE user_id = $1 AND revoked_at IS NULL RETURNING id`,
    [userId, new Date().toISOString()],
  );
  const count = rows.length;
  logger.info('Todas las sesiones del usuario revocadas', { userId, count });
  return count;
}

/** Sesiones ACTIVAS de un usuario, agregadas por familia (en memoria). */
async function listActiveSessionsForUser(userId) {
  const { rows } = await query(
    `SELECT family_id, device_info, ip_address, created_at, expires_at
     FROM refresh_tokens WHERE user_id = $1 AND revoked_at IS NULL
     ORDER BY created_at DESC`,
    [userId],
  );

  const byFamily = new Map();
  for (const row of rows) {
    const existing = byFamily.get(row.family_id);
    if (!existing) {
      byFamily.set(row.family_id, {
        familyId:   row.family_id,
        device:     row.device_info,
        ip:         row.ip_address,
        lastActive: row.created_at,
        started:    row.created_at,
        expiresAt:  row.expires_at,
      });
    } else if (row.created_at < existing.started) {
      existing.started = row.created_at;
    }
  }
  return Array.from(byFamily.values());
}

/** Revoca una familia SOLO si pertenece al usuario (anti BOLA/IDOR). @returns {Promise<number>} */
async function revokeFamilyForUser(userId, familyId) {
  const { rows } = await query(
    `UPDATE refresh_tokens SET revoked_at = $3
     WHERE user_id = $1 AND family_id = $2 AND revoked_at IS NULL
     RETURNING id`,
    [userId, familyId, new Date().toISOString()],
  );
  return rows.length;
}

module.exports = {
  issue,
  findByHash,
  consumeAtomically,
  revokeFamily,
  revokeAllForUser,
  listActiveSessionsForUser,
  revokeFamilyForUser,
};
