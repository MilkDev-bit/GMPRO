/**
 * @file services/auth-service/src/models/refreshTokenModel.js
 * @description Capa de datos de refresh tokens con FAMILIAS y REUSE DETECTION.
 *
 * Modelo:
 *   · Cada login abre una FAMILIA (family_id). Cada /refresh consume el token
 *     actual (is_consumed=true) y emite el siguiente en la MISMA familia.
 *   · Un token solo es canjeable una vez. Si llega uno ya consumido → REUSE →
 *     el controlador revoca la familia entera (mitiga robo, RFC 6819 / OAuth BCP).
 *   · Soporta N familias por usuario → multi-dispositivo (phone/tablet/web).
 *
 * Solo se almacena el SHA-256 del token; el texto plano vive en la cookie
 * HttpOnly del cliente.
 */

'use strict';

const { getSupabaseClient } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:refreshTokenModel');

const TABLE = 'refresh_tokens';

/**
 * Emite (persiste) un nuevo refresh token dentro de una familia.
 * @param {object} p
 * @param {string} p.userId
 * @param {string} p.tokenHash        - SHA-256 hex del token opaco
 * @param {string} p.familyId         - UUID de la familia de sesión
 * @param {string} p.expiresAt        - ISO timestamp
 * @param {string|null} [p.deviceInfo]
 * @param {string|null} [p.ipAddress]
 * @returns {Promise<object>} fila insertada
 */
async function issue({ userId, tokenHash, familyId, expiresAt, deviceInfo = null, ipAddress = null }) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .insert({
      user_id:     userId,
      family_id:   familyId,
      token_hash:  tokenHash,
      expires_at:  expiresAt,
      device_info: deviceInfo ? String(deviceInfo).slice(0, 255) : null,
      ip_address:  ipAddress ? String(ipAddress).slice(0, 64) : null,
    })
    .select('id, family_id, expires_at')
    .single();

  if (error) throw error;
  return data;
}

/**
 * Busca un token por su hash. Devuelve la fila (con estado) o null.
 * @param {string} tokenHash
 * @returns {Promise<object|null>}
 */
async function findByHash(tokenHash) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .select('id, user_id, family_id, is_consumed, expires_at, revoked_at')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (error) throw error;
  return data || null;
}

/**
 * Consume un token de forma ATÓMICA: marca is_consumed=true SOLO si aún estaba
 * sin consumir y sin revocar. El filtro en el UPDATE es la sección crítica: si
 * dos requests concurrentes traen el mismo token, solo una consigue consumirlo;
 * la otra recibe 0 filas afectadas y el controlador la trata como REUSE.
 *
 * @param {string} id - id de la fila del token
 * @returns {Promise<boolean>} true si ESTA llamada lo consumió; false si ya lo estaba
 */
async function consumeAtomically(id) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .update({ is_consumed: true, consumed_at: new Date().toISOString() })
    .eq('id', id)
    .eq('is_consumed', false)
    .is('revoked_at', null)
    .select('id');

  if (error) throw error;
  return Array.isArray(data) && data.length === 1;
}

/**
 * Revoca TODA una familia (reuse detectado o logout de un dispositivo).
 * Idempotente: solo toca filas aún vigentes.
 * @param {string} familyId
 * @returns {Promise<number>} nº de tokens revocados
 */
async function revokeFamily(familyId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .update({ revoked_at: new Date().toISOString() })
    .eq('family_id', familyId)
    .is('revoked_at', null)
    .select('id');

  if (error) throw error;
  const count = Array.isArray(data) ? data.length : 0;
  if (count > 0) logger.warn('Familia de refresh tokens revocada', { familyId, count });
  return count;
}

/**
 * Revoca TODAS las familias de un usuario (cambio de contraseña, baja de cuenta,
 * "cerrar sesión en todos los dispositivos").
 * @param {string} userId
 * @returns {Promise<number>}
 */
async function revokeAllForUser(userId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .update({ revoked_at: new Date().toISOString() })
    .eq('user_id', userId)
    .is('revoked_at', null)
    .select('id');

  if (error) throw error;
  const count = Array.isArray(data) ? data.length : 0;
  logger.info('Todas las sesiones del usuario revocadas', { userId, count });
  return count;
}

/**
 * Lista las sesiones ACTIVAS de un usuario, agregadas por familia. Cada familia
 * tiene varios tokens (rotaciones); se colapsa a una entrada por sesión con sus
 * metadatos de dispositivo. Un usuario tiene pocas familias/rotaciones, así que
 * se agrega en memoria (evita depender de una RPC de GROUP BY en Postgres).
 * @param {string} userId
 * @returns {Promise<Array<{familyId,device,ip,started,lastActive,expiresAt}>>}
 */
async function listActiveSessionsForUser(userId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .select('family_id, device_info, ip_address, created_at, expires_at')
    .eq('user_id', userId)
    .is('revoked_at', null)
    .order('created_at', { ascending: false }); // más reciente primero

  if (error) throw error;

  const byFamily = new Map();
  for (const row of data || []) {
    const existing = byFamily.get(row.family_id);
    if (!existing) {
      // Primera fila vista (la más reciente) → representa la actividad actual.
      byFamily.set(row.family_id, {
        familyId:   row.family_id,
        device:     row.device_info,
        ip:         row.ip_address,
        lastActive: row.created_at,
        started:    row.created_at,
        expiresAt:  row.expires_at,
      });
    } else if (row.created_at < existing.started) {
      existing.started = row.created_at; // fila más antigua → inicio de la sesión
    }
  }
  return Array.from(byFamily.values());
}

/**
 * Revoca una familia SOLO si pertenece al usuario indicado (protección BOLA/IDOR).
 * El filtro por user_id impide revocar la sesión de otra persona.
 * @param {string} userId
 * @param {string} familyId
 * @returns {Promise<number>} nº de tokens revocados (0 = no existe o no es del usuario)
 */
async function revokeFamilyForUser(userId, familyId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .update({ revoked_at: new Date().toISOString() })
    .eq('user_id', userId)     // ← candado de propiedad: nunca toca familias ajenas
    .eq('family_id', familyId)
    .is('revoked_at', null)
    .select('id');

  if (error) throw error;
  return Array.isArray(data) ? data.length : 0;
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
