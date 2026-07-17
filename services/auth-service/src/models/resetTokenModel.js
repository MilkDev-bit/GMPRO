/**
 * @file services/auth-service/src/models/resetTokenModel.js
 * @description Modelo para tokens de restablecimiento de contraseña.
 */

'use strict';

const { getSupabaseClient } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:resetTokenModel');

/**
 * Crea un nuevo token de reset de contraseña.
 *
 * @param {string} usuarioId - UUID del usuario
 * @param {string} tokenHash - SHA-256 del token en texto plano
 * @returns {Promise<object>} Registro creado
 */
async function create(usuarioId, tokenHash) {
  const db = getSupabaseClient();

  // Primero invalidar cualquier token anterior del mismo usuario
  await db
    .from('tokens_password_reset')
    .update({ usado: true })
    .eq('usuario_id', usuarioId)
    .eq('usado', false);

  const { data, error } = await db
    .from('tokens_password_reset')
    .insert({
      usuario_id: usuarioId,
      token_hash: tokenHash,
      // expira_en: DEFAULT en Supabase = NOW() + INTERVAL '1 hour'
    })
    .select('id, expira_en')
    .single();

  if (error) throw error;
  logger.info('Token de reset creado', { userId: usuarioId, tokenId: data.id });
  return data;
}

/**
 * Busca y valida un token de reset por su hash.
 * Retorna null si el token no existe, ya fue usado, o expiró.
 *
 * @param {string} tokenHash - SHA-256 del token recibido por el usuario
 * @returns {Promise<{id: string, usuario_id: string}|null>}
 */
async function findValidToken(tokenHash) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('tokens_password_reset')
    .select('id, usuario_id, expira_en')
    .eq('token_hash', tokenHash)
    .eq('usado', false)
    .gt('expira_en', new Date().toISOString())  // No expirado
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }

  return data;
}

/**
 * Marca un token como usado (solo puede usarse una vez).
 *
 * @param {string} tokenId - UUID del registro en tokens_password_reset
 * @returns {Promise<void>}
 */
async function markAsUsed(tokenId) {
  const db = getSupabaseClient();

  const { error } = await db
    .from('tokens_password_reset')
    .update({ usado: true })
    .eq('id', tokenId);

  if (error) throw error;
}

module.exports = { create, findValidToken, markAsUsed };
