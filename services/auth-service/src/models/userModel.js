/**
 * @file services/auth-service/src/models/userModel.js
 * @description Capa de acceso a datos para la tabla auth_service_db.usuarios.
 *
 * Mínimo privilegio (CLD-1): opera vía `pg` con el rol svc_auth (query()),
 * SQL SIEMPRE parametrizado ($1,$2,…) — nunca concatenar valores.
 *
 * SEGURIDAD:
 *   • Nunca se retorna password_hash al caller (SAFE_COLUMNS lo excluye).
 *   • Los campos sensibles se listan explícitamente en los SELECT.
 *   • El cifrado/descifrado de historial_clinico ocurre en la capa de servicio.
 */

'use strict';

const bcrypt  = require('bcrypt');
const crypto  = require('crypto');
const env     = require('../config/environment');
const { query } = require('../config/database');
const refreshTokenModel = require('./refreshTokenModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:userModel');

// Columnas seguras a retornar (sin hashes ni tokens)
const SAFE_COLUMNS = [
  'id', 'email', 'nombre', 'apellido_paterno', 'apellido_materno',
  'telefono', 'fecha_nacimiento', 'sexo_biologico', 'estatura_cm',
  'peso_kg', 'nivel_actividad', 'historial_clinico', 'contacto_emergencia',
  'email_verificado', 'activo', 'rol', 'ultimo_login',
  'intentos_fallidos', 'bloqueado_hasta', 'creado_en', 'actualizado_en',
  'pin_terminal',
].join(', ');

// Columnas para autenticación (incluye el hash para comparar en login).
const AUTH_COLUMNS = `${SAFE_COLUMNS}, password_hash`;

/** Busca un usuario por email (activo, no eliminado). Incluye password_hash. */
async function findByEmailForAuth(email) {
  const { rows } = await query(
    `SELECT ${AUTH_COLUMNS} FROM usuarios
     WHERE email = $1 AND eliminado_en IS NULL LIMIT 1`,
    [email.toLowerCase().trim()],
  );
  return rows[0] || null;
}

/** Busca un usuario por ID (sin hash). */
async function findById(id) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM usuarios
     WHERE id = $1 AND eliminado_en IS NULL LIMIT 1`,
    [id],
  );
  return rows[0] || null;
}

/** Crea un nuevo usuario. @returns {Promise<object>} sin password_hash */
async function create(userData) {
  try {
    const { rows } = await query(
      `INSERT INTO usuarios
         (email, password_hash, nombre, apellido_paterno, apellido_materno,
          telefono, rol, email_verificado, activo)
       VALUES ($1,$2,$3,$4,$5,$6,$7,false,true)
       RETURNING ${SAFE_COLUMNS}`,
      [
        userData.email.toLowerCase().trim(),
        userData.password_hash,
        userData.nombre,
        userData.apellido_paterno,
        userData.apellido_materno || null,
        userData.telefono || null,
        userData.rol || 'miembro',
      ],
    );
    const data = rows[0];
    logger.info('Usuario creado', { userId: data.id, rol: data.rol });
    return data;
  } catch (error) {
    if (error.code === '23505') {   // unique_violation (email duplicado)
      const duplicateError = new Error('El email ya está registrado.');
      duplicateError.status = 409;
      throw duplicateError;
    }
    throw error;
  }
}

/** Bookkeeping de login exitoso (no lanza; solo loguea si falla). */
async function recordSuccessfulLogin(id) {
  try {
    await query(
      `UPDATE usuarios SET ultimo_login = $2, intentos_fallidos = 0, bloqueado_hasta = NULL
       WHERE id = $1`,
      [id, new Date().toISOString()],
    );
  } catch (error) {
    logger.error('Error actualizando login exitoso', { userId: id, error: error.message });
  }
}

/** Incrementa intentos fallidos y bloquea progresivamente (OWASP A07). */
async function recordFailedLogin(id, currentAttempts) {
  const newAttempts = currentAttempts + 1;
  let blockedUntil = null;
  if (newAttempts >= 10)      blockedUntil = new Date(Date.now() + 24 * 60 * 60_000);
  else if (newAttempts >= 7)  blockedUntil = new Date(Date.now() + 60 * 60_000);
  else if (newAttempts >= 5)  blockedUntil = new Date(Date.now() + 15 * 60_000);

  try {
    await query(
      `UPDATE usuarios SET intentos_fallidos = $2, bloqueado_hasta = $3 WHERE id = $1`,
      [id, newAttempts, blockedUntil?.toISOString() || null],
    );
  } catch (error) {
    logger.error('Error registrando login fallido', { userId: id, error: error.message });
  }
  return { blocked: !!blockedUntil, blockedUntil };
}

/** Marca el email como verificado e invalida el token de verificación. */
async function verifyEmail(id) {
  await query(
    `UPDATE usuarios SET email_verificado = true, token_verificacion = NULL WHERE id = $1`,
    [id],
  );
  logger.info('Email verificado', { userId: id });
}

/** Actualiza el hash de contraseña y revoca TODAS las sesiones del usuario. */
async function updatePassword(id, newPasswordHash) {
  await query(
    `UPDATE usuarios SET password_hash = $2, intentos_fallidos = 0, bloqueado_hasta = NULL
     WHERE id = $1`,
    [id, newPasswordHash],
  );
  await refreshTokenModel.revokeAllForUser(id);
  logger.info('Contraseña actualizada y sesiones revocadas', { userId: id });
}

/** Actualiza datos de perfil (nunca email/password). @returns {Promise<object>} */
async function updateProfile(id, profileData) {
  const allowedFields = [
    'nombre', 'apellido_paterno', 'apellido_materno', 'telefono',
    'fecha_nacimiento', 'sexo_biologico', 'estatura_cm', 'peso_kg',
    'nivel_actividad', 'historial_clinico', 'contacto_emergencia',
  ];

  const safeUpdate = {};
  for (const field of allowedFields) {
    if (field in profileData) safeUpdate[field] = profileData[field];
  }
  if (Object.keys(safeUpdate).length === 0) {
    const err = new Error('No se proporcionaron campos válidos para actualizar.');
    err.status = 400;
    throw err;
  }

  const cols = Object.keys(safeUpdate);
  const setClause = cols.map((c, i) => `"${c}" = $${i + 2}`).join(', ');
  const vals = cols.map((c) => safeUpdate[c]);

  const { rows } = await query(
    `UPDATE usuarios SET ${setClause} WHERE id = $1 RETURNING ${SAFE_COLUMNS}`,
    [id, ...vals],
  );
  if (!rows[0]) { const e = new Error('Usuario no encontrado.'); e.status = 404; throw e; }
  return rows[0];
}

/** Busca o crea un usuario vía OAuth nativo (Google/Apple). Email pre-verificado. */
async function findOrCreateByOAuth({ email, nombre, apellido_paterno = 'Socio' }) {
  const cleanEmail = email.toLowerCase().trim();

  const { rows: found } = await query(
    `SELECT ${SAFE_COLUMNS} FROM usuarios WHERE email = $1 AND eliminado_en IS NULL LIMIT 1`,
    [cleanEmail],
  );
  const existingUser = found[0];
  if (existingUser) {
    if (!existingUser.email_verificado) {
      await query(`UPDATE usuarios SET email_verificado = true WHERE id = $1`, [existingUser.id]);
      existingUser.email_verificado = true;
    }
    return existingUser;
  }

  const randomPasswordHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), env.BCRYPT_ROUNDS);
  const { rows } = await query(
    `INSERT INTO usuarios
       (email, password_hash, nombre, apellido_paterno, rol, email_verificado, activo)
     VALUES ($1,$2,$3,$4,'miembro',true,true)
     RETURNING ${SAFE_COLUMNS}`,
    [cleanEmail, randomPasswordHash, nombre || 'Socio', apellido_paterno || 'GymPro'],
  );
  logger.info('Nuevo usuario creado mediante OAuth nativo', { userId: rows[0].id, email: cleanEmail });
  return rows[0];
}

/** Soft delete: marca eliminado_en y revoca sesiones. */
async function softDelete(id) {
  await query(
    `UPDATE usuarios SET eliminado_en = $2, activo = false WHERE id = $1`,
    [id, new Date().toISOString()],
  );
  await refreshTokenModel.revokeAllForUser(id);
  logger.info('Usuario eliminado (soft delete) y sesiones revocadas', { userId: id });
}

/** pin_terminal de un usuario (para sync ZKTeco). */
async function findPinTerminalByUserId(usuarioId) {
  const { rows } = await query(
    `SELECT id, nombre, apellido_paterno, pin_terminal FROM usuarios
     WHERE id = $1 AND eliminado_en IS NULL LIMIT 1`,
    [usuarioId],
  );
  return rows[0] || null;
}

/** Asigna un pin_terminal único vía la función SQL atómica assign_pin_terminal(). */
async function assignPinTerminal(usuarioId) {
  const { rows } = await query(
    `SELECT auth_service_db.assign_pin_terminal($1) AS pin`,
    [usuarioId],
  );
  const pin = rows[0].pin;
  logger.info('pin_terminal asignado a usuario via ZKTeco sync', { usuarioId, pin });
  return pin;
}

// ── ADMIN: listado y gestión de miembros ─────────────────────────────────────
/** Lista miembros con búsqueda opcional (saneada) por nombre/email. */
async function listMembers({ search = '', limit = 100 } = {}) {
  const lim = Math.min(limit, 200);
  const safe = String(search).replace(/[^a-zA-Z0-9@._\-\s]/g, '').trim().slice(0, 60);
  if (safe) {
    const { rows } = await query(
      `SELECT ${SAFE_COLUMNS} FROM usuarios
       WHERE eliminado_en IS NULL AND (email ILIKE $1 OR nombre ILIKE $1)
       ORDER BY creado_en DESC LIMIT $2`,
      [`%${safe}%`, lim],
    );
    return rows;
  }
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM usuarios
     WHERE eliminado_en IS NULL ORDER BY creado_en DESC LIMIT $1`,
    [lim],
  );
  return rows;
}

/** Activa/suspende un miembro (soft-lock). */
async function setActive(id, activo) {
  const { rows } = await query(
    `UPDATE usuarios SET activo = $2 WHERE id = $1 AND eliminado_en IS NULL
     RETURNING ${SAFE_COLUMNS}`,
    [id, activo],
  );
  if (!rows[0]) { const e = new Error('Usuario no encontrado.'); e.status = 404; throw e; }
  return rows[0];
}

module.exports = {
  findByEmailForAuth,
  findById,
  create,
  findOrCreateByOAuth,
  recordSuccessfulLogin,
  recordFailedLogin,
  verifyEmail,
  updatePassword,
  updateProfile,
  softDelete,
  findPinTerminalByUserId,
  assignPinTerminal,
  listMembers,
  setActive,
};
