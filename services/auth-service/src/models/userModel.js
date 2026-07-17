/**
 * @file services/auth-service/src/models/userModel.js
 * @description Capa de acceso a datos para la tabla auth_service_db.usuarios.
 *
 * FILOSOFÍA:
 *   Este modelo encapsula TODA interacción con Supabase para la entidad usuario.
 *   Los controllers nunca construyen queries directamente — solo llaman a estos métodos.
 *   Esto permite cambiar Supabase por otro ORM/DB sin tocar los controllers.
 *
 * SEGURIDAD:
 *   • Nunca se retorna password_hash ni refresh_token_hash al caller
 *   • Los campos sensibles se listan explícitamente en los SELECT
 *   • El cifrado/descifrado de historial_clinico ocurre en la capa de servicio
 */

'use strict';

const bcrypt  = require('bcrypt');
const crypto  = require('crypto');
const env     = require('../config/environment');
const { getSupabaseClient } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:userModel');

// Columnas seguras a retornar en la mayoría de queries (sin hashes ni tokens)
const SAFE_COLUMNS = [
  'id', 'email', 'nombre', 'apellido_paterno', 'apellido_materno',
  'telefono', 'fecha_nacimiento', 'sexo_biologico', 'estatura_cm',
  'peso_kg', 'nivel_actividad', 'historial_clinico', 'contacto_emergencia',
  'email_verificado', 'activo', 'rol', 'ultimo_login',
  'intentos_fallidos', 'bloqueado_hasta', 'creado_en', 'actualizado_en',
  'pin_terminal',  // PIN numérico asignado a la terminal biométrica ZKTeco
].join(', ');

// Columnas para autenticación (incluye el hash para comparar)
const AUTH_COLUMNS = `${SAFE_COLUMNS}, password_hash, refresh_token_hash`;

/**
 * Busca un usuario por email. Solo para usuarios activos y no eliminados.
 * Incluye password_hash para validación de login.
 *
 * @param {string} email
 * @returns {Promise<object|null>}
 */
async function findByEmailForAuth(email) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('usuarios')
    .select(AUTH_COLUMNS)
    .eq('email', email.toLowerCase().trim())
    .is('eliminado_en', null)         // Excluir cuentas eliminadas (soft delete)
    .limit(1)
    .single();

  if (error) {
    // PGRST116: no rows found — no es un error real para esta consulta
    if (error.code === 'PGRST116') return null;
    logger.error('Error en findByEmailForAuth', { error: error.message });
    throw error;
  }

  return data;
}

/**
 * Busca un usuario por ID (sin hash de contraseña).
 *
 * @param {string} id - UUID
 * @returns {Promise<object|null>}
 */
async function findById(id) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('usuarios')
    .select(SAFE_COLUMNS)
    .eq('id', id)
    .is('eliminado_en', null)
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }

  return data;
}

/**
 * Crea un nuevo usuario en la base de datos.
 *
 * @param {object} userData
 * @param {string} userData.email
 * @param {string} userData.password_hash  - Ya hasheado con bcrypt
 * @param {string} userData.nombre
 * @param {string} userData.apellido_paterno
 * @param {string} [userData.apellido_materno]
 * @param {string} [userData.telefono]
 * @param {string} [userData.rol]
 * @returns {Promise<object>}  Usuario creado (sin password_hash)
 */
async function create(userData) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('usuarios')
    .insert({
      email:             userData.email.toLowerCase().trim(),
      password_hash:     userData.password_hash,
      nombre:            userData.nombre,
      apellido_paterno:  userData.apellido_paterno,
      apellido_materno:  userData.apellido_materno || null,
      telefono:          userData.telefono || null,
      rol:               userData.rol || 'miembro',
      email_verificado:  false,
      activo:            true,
    })
    .select(SAFE_COLUMNS)
    .single();

  if (error) {
    // Código 23505: unique_violation (email duplicado)
    if (error.code === '23505') {
      const duplicateError = new Error('El email ya está registrado.');
      duplicateError.status = 409;
      throw duplicateError;
    }
    throw error;
  }

  logger.info('Usuario creado', { userId: data.id, rol: data.rol });
  return data;
}

/**
 * Actualiza el último login y limpia el contador de intentos fallidos.
 * Llamada después de un login exitoso.
 *
 * @param {string} id - UUID del usuario
 * @param {string} refreshTokenHash - SHA-256 del nuevo refresh token
 * @returns {Promise<void>}
 */
async function recordSuccessfulLogin(id, refreshTokenHash) {
  const db = getSupabaseClient();

  const { error } = await db
    .from('usuarios')
    .update({
      ultimo_login:       new Date().toISOString(),
      intentos_fallidos:  0,
      bloqueado_hasta:    null,   // Limpiar bloqueo si existía
      refresh_token_hash: refreshTokenHash,
    })
    .eq('id', id);

  if (error) logger.error('Error actualizando login exitoso', { userId: id, error: error.message });
}

/**
 * Incrementa el contador de intentos fallidos y opcionalmente bloquea la cuenta.
 * OWASP A07: Previene fuerza bruta con bloqueo progresivo.
 *
 * @param {string} id
 * @param {number} currentAttempts - Intentos actuales antes de este fallo
 * @returns {Promise<{ blocked: boolean, blockedUntil: Date|null }>}
 */
async function recordFailedLogin(id, currentAttempts) {
  const db = getSupabaseClient();
  const newAttempts = currentAttempts + 1;

  // Bloquear tras 5 intentos fallidos: 15 min, luego 1h, luego 24h
  let blockedUntil = null;
  if (newAttempts >= 10) {
    blockedUntil = new Date(Date.now() + 24 * 60 * 60_000);  // 24 horas
  } else if (newAttempts >= 7) {
    blockedUntil = new Date(Date.now() + 60 * 60_000);       // 1 hora
  } else if (newAttempts >= 5) {
    blockedUntil = new Date(Date.now() + 15 * 60_000);       // 15 minutos
  }

  const { error } = await db
    .from('usuarios')
    .update({
      intentos_fallidos: newAttempts,
      bloqueado_hasta:   blockedUntil?.toISOString() || null,
    })
    .eq('id', id);

  if (error) logger.error('Error registrando login fallido', { userId: id, error: error.message });

  return { blocked: !!blockedUntil, blockedUntil };
}

/**
 * Marca el email del usuario como verificado e invalida el token de verificación.
 *
 * @param {string} id
 * @returns {Promise<void>}
 */
async function verifyEmail(id) {
  const db = getSupabaseClient();

  const { error } = await db
    .from('usuarios')
    .update({
      email_verificado:  true,
      token_verificacion: null,  // Invalidar token usado
    })
    .eq('id', id);

  if (error) throw error;
  logger.info('Email verificado', { userId: id });
}

/**
 * Actualiza el hash de la contraseña e invalida todos los refresh tokens activos.
 * Llamada después de un reset o cambio de contraseña exitoso.
 *
 * @param {string} id
 * @param {string} newPasswordHash
 * @returns {Promise<void>}
 */
async function updatePassword(id, newPasswordHash) {
  const db = getSupabaseClient();

  const { error } = await db
    .from('usuarios')
    .update({
      password_hash:      newPasswordHash,
      refresh_token_hash: null,    // Invalidar todas las sesiones activas
      intentos_fallidos:  0,
      bloqueado_hasta:    null,
    })
    .eq('id', id);

  if (error) throw error;
  logger.info('Contraseña actualizada', { userId: id });
}

/**
 * Actualiza los datos de perfil del usuario (no credenciales).
 *
 * @param {string} id
 * @param {Partial<object>} profileData
 * @returns {Promise<object>} Usuario actualizado
 */
async function updateProfile(id, profileData) {
  const db = getSupabaseClient();

  // Permitir solo campos de perfil — nunca permitir actualizar email o password aquí
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

  const { data, error } = await db
    .from('usuarios')
    .update(safeUpdate)
    .eq('id', id)
    .select(SAFE_COLUMNS)
    .single();

  if (error) throw error;
  return data;
}

/**
 * Busca o crea un usuario autenticado mediante proveedor nativo OAuth (Google / Apple).
 * Al autenticarse a través de un proveedor nativo, el email se considera pre-verificado.
 *
 * @param {object} oauthData
 * @param {string} oauthData.email
 * @param {string} oauthData.nombre
 * @param {string} [oauthData.apellido_paterno]
 * @returns {Promise<object>} Usuario de DB listo para generar JWT
 */
async function findOrCreateByOAuth({ email, nombre, apellido_paterno = 'Socio' }) {
  const db = getSupabaseClient();
  const cleanEmail = email.toLowerCase().trim();

  // 1. Intentar buscar por email existente
  const { data: existingUser, error: findErr } = await db
    .from('usuarios')
    .select(SAFE_COLUMNS)
    .eq('email', cleanEmail)
    .is('eliminado_en', null)
    .maybeSingle();

  if (findErr && findErr.code !== 'PGRST116') {
    logger.error('Error buscando usuario OAuth en DB', { error: findErr.message });
    throw findErr;
  }

  if (existingUser) {
    // Si existía pero no había verificado email, lo verificamos al entrar con Google/Apple
    if (!existingUser.email_verificado) {
      await db.from('usuarios').update({ email_verificado: true }).eq('id', existingUser.id);
      existingUser.email_verificado = true;
    }
    return existingUser;
  }

  // 2. Si no existe, crear cuenta con contraseña aleatoria criptográfica y email verificado
  const randomPasswordHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), env.BCRYPT_ROUNDS);
  const { data: newUser, error: createErr } = await db
    .from('usuarios')
    .insert({
      email: cleanEmail,
      password_hash: randomPasswordHash,
      nombre: nombre || 'Socio',
      apellido_paterno: apellido_paterno || 'GymPro',
      rol: 'miembro',
      email_verificado: true,
      activo: true,
    })
    .select(SAFE_COLUMNS)
    .single();

  if (createErr) {
    logger.error('Error creando usuario vía OAuth', { error: createErr.message });
    throw createErr;
  }

  logger.info('Nuevo usuario creado mediante OAuth nativo', { userId: newUser.id, email: cleanEmail });
  return newUser;
}

/**
 * Soft delete: marca el usuario como eliminado sin borrar el registro.
 * Preserva el historial de accesos y pagos vinculados al usuario_id.
 *
 * @param {string} id
 * @returns {Promise<void>}
 */
async function softDelete(id) {
  const db = getSupabaseClient();

  const { error } = await db
    .from('usuarios')
    .update({
      eliminado_en:       new Date().toISOString(),
      activo:             false,
      refresh_token_hash: null,   // Invalida todas las sesiones
    })
    .eq('id', id);

  if (error) throw error;
  logger.info('Usuario eliminado (soft delete)', { userId: id });
}

/**
 * Obtiene el pin_terminal de un usuario para la integración con ZKTeco ADMS.
 * Solo retorna el UUID, nombre y pin_terminal (campos mínimos para el sync).
 *
 * @param {string} usuarioId - UUID del usuario
 * @returns {Promise<{id: string, nombre: string, pin_terminal: number|null}|null>}
 */
async function findPinTerminalByUserId(usuarioId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('usuarios')
    .select('id, nombre, apellido_paterno, pin_terminal')
    .eq('id', usuarioId)
    .is('eliminado_en', null)
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/**
 * Asigna un pin_terminal único a un usuario si aún no tiene uno.
 * Invoca la función SQL assign_pin_terminal() que usa una secuencia
 * interna para garantizar unicidad sin condiciones de carrera.
 *
 * @param {string} usuarioId - UUID del usuario
 * @returns {Promise<number>} PIN asignado o existente
 */
async function assignPinTerminal(usuarioId) {
  const db = getSupabaseClient();

  // Llamar a la función SQL segura que maneja la secuencia atómicamente
  const { data, error } = await db.rpc('assign_pin_terminal', {
    p_usuario_id: usuarioId,
  });

  if (error) {
    logger.error('Error asignando pin_terminal al usuario', {
      usuarioId, error: error.message,
    });
    throw error;
  }

  logger.info('pin_terminal asignado a usuario via ZKTeco sync', {
    usuarioId, pin: data,
  });
  return data;
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
};
