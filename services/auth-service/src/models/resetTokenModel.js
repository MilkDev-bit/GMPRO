/**
 * @file services/auth-service/src/models/resetTokenModel.js
 * @description Modelo para tokens de restablecimiento de contraseña.
 * Mínimo privilegio (CLD-1): pg con rol svc_auth, SQL parametrizado.
 */

'use strict';

const { query } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:resetTokenModel');

/** Crea un token de reset (invalida los anteriores del usuario primero). */
async function create(usuarioId, tokenHash) {
  // Invalidar cualquier token anterior vigente del mismo usuario.
  await query(
    `UPDATE tokens_password_reset SET usado = true
     WHERE usuario_id = $1 AND usado = false`,
    [usuarioId],
  );

  // expira_en tiene DEFAULT (NOW() + 1 hora) en el schema.
  const { rows } = await query(
    `INSERT INTO tokens_password_reset (usuario_id, token_hash)
     VALUES ($1, $2)
     RETURNING id, expira_en`,
    [usuarioId, tokenHash],
  );
  logger.info('Token de reset creado', { userId: usuarioId, tokenId: rows[0].id });
  return rows[0];
}

/** Busca y valida un token por hash (no usado, no expirado). @returns {Promise<object|null>} */
async function findValidToken(tokenHash) {
  const { rows } = await query(
    `SELECT id, usuario_id, expira_en FROM tokens_password_reset
     WHERE token_hash = $1 AND usado = false AND expira_en > $2
     LIMIT 1`,
    [tokenHash, new Date().toISOString()],
  );
  return rows[0] || null;
}

/** Marca un token como usado (un solo uso). */
async function markAsUsed(tokenId) {
  await query(`UPDATE tokens_password_reset SET usado = true WHERE id = $1`, [tokenId]);
}

module.exports = { create, findValidToken, markAsUsed };
