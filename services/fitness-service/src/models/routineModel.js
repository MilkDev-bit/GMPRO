/**
 * @file services/fitness-service/src/models/routineModel.js
 * @description Capa de datos para rutinas de entrenamiento y ejercicios asignados.
 */

'use strict';

const { getSupabaseClient }   = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:routineModel');

/**
 * Obtiene las rutinas asignadas o personalizadas de un usuario.
 *
 * @param {string} usuarioId
 * @returns {Promise<object[]>}
 */
async function getUserRoutines(usuarioId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('rutinas')
    .select('*, rutina_ejercicios(*, ejercicios(*))')
    .eq('usuario_id', usuarioId)
    .order('creado_at', { ascending: false });

  if (error) {
    logger.error('Error obteniendo rutinas del usuario', { usuarioId, error: error.message });
    throw error;
  }
  return data || [];
}

/**
 * Crea una nueva rutina para el usuario con sus ejercicios y sets/reps.
 *
 * @param {object} routineData
 * @param {string} routineData.usuario_id
 * @param {string} routineData.nombre
 * @param {string} [routineData.descripcion]
 * @param {string} [routineData.nivel] - 'beginner' | 'intermediate' | 'advanced'
 * @param {object[]} [routineData.ejercicios] - [{ ejercicio_id, series, repeticiones, descanso_seg }]
 * @returns {Promise<object>}
 */
async function createRoutine({
  usuario_id,
  nombre,
  descripcion = null,
  nivel = 'intermediate',
  ejercicios = [],
}) {
  const db = getSupabaseClient();

  // 1. Insertar la rutina cabecera
  const { data: rutina, error: routineErr } = await db
    .from('rutinas')
    .insert({
      usuario_id,
      nombre,
      descripcion,
      nivel,
      creado_at: new Date().toISOString(),
    })
    .select('*')
    .single();

  if (routineErr) {
    logger.error('Error al insertar rutina en DB', { error: routineErr.message });
    throw routineErr;
  }

  // 2. Insertar ítems en rutina_ejercicios si se proporcionaron
  if (Array.isArray(ejercicios) && ejercicios.length > 0) {
    const itemsToInsert = ejercicios.map((ej, index) => ({
      rutina_id:       rutina.id,
      ejercicio_id:    ej.ejercicio_id,
      series:          ej.series || 3,
      repeticiones:    ej.repeticiones || 12,
      descanso_seg:    ej.descanso_seg || 60,
      orden:           index + 1,
    }));

    const { error: itemsErr } = await db
      .from('rutina_ejercicios')
      .insert(itemsToInsert);

    if (itemsErr) {
      logger.error('Error insertando ejercicios de la rutina', { error: itemsErr.message });
      throw itemsErr;
    }
  }

  logger.info('Rutina creada con éxito', { rutinaId: rutina.id, usuarioId: usuario_id });
  return rutina;
}

/**
 * Elimina una rutina del usuario.
 *
 * @param {string} rutinaId
 * @param {string} usuarioId - Para verificación de propiedad
 * @returns {Promise<boolean>}
 */
async function deleteRoutine(rutinaId, usuarioId) {
  const db = getSupabaseClient();
  const { error, count } = await db
    .from('rutinas')
    .delete({ count: 'exact' })
    .eq('id', rutinaId)
    .eq('usuario_id', usuarioId);

  if (error) throw error;
  return count > 0;
}

module.exports = {
  getUserRoutines,
  createRoutine,
  deleteRoutine,
};
