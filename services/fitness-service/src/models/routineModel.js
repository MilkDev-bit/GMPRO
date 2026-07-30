/**
 * @file services/fitness-service/src/models/routineModel.js
 * @description Capa de datos para rutinas de entrenamiento y ejercicios asignados.
 * Mínimo privilegio (CLD-1): pg con rol svc_fitness, SQL parametrizado.
 */

'use strict';

const { query, getPool }      = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:routineModel');

/**
 * Rutinas de un usuario con sus ejercicios anidados.
 * Equivale al embed PostgREST `*, rutina_ejercicios(*, ejercicios(*))`.
 * @param {string} usuarioId
 * @returns {Promise<object[]>}
 */
async function getUserRoutines(usuarioId) {
  const { rows } = await query(
    `SELECT r.*,
       COALESCE((
         SELECT jsonb_agg(
                  jsonb_build_object(
                    'id', re.id, 'rutina_id', re.rutina_id, 'ejercicio_id', re.ejercicio_id,
                    'series', re.series, 'repeticiones', re.repeticiones,
                    'descanso_seg', re.descanso_seg, 'orden', re.orden,
                    'ejercicios', to_jsonb(e.*)
                  ) ORDER BY re.orden)
         FROM rutina_ejercicios re
         JOIN ejercicios e ON e.id = re.ejercicio_id
         WHERE re.rutina_id = r.id
       ), '[]'::jsonb) AS rutina_ejercicios
     FROM rutinas r
     WHERE r.usuario_id = $1
     ORDER BY r.creado_at DESC`,
    [usuarioId],
  );
  return rows;
}

/**
 * Crea una rutina con sus ejercicios en una TRANSACCIÓN (cabecera + ítems).
 * @param {object} routineData
 * @returns {Promise<object>} la rutina creada
 */
async function createRoutine({
  usuario_id,
  nombre,
  descripcion = null,
  nivel = 'intermediate',
  ejercicios = [],
}) {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `INSERT INTO rutinas (usuario_id, nombre, descripcion, nivel, creado_at)
       VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [usuario_id, nombre, descripcion, nivel, new Date().toISOString()],
    );
    const rutina = rows[0];

    if (Array.isArray(ejercicios) && ejercicios.length > 0) {
      let idx = 0;
      for (const ej of ejercicios) {
        idx += 1;
        await client.query(
          `INSERT INTO rutina_ejercicios (rutina_id, ejercicio_id, series, repeticiones, descanso_seg, orden)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [rutina.id, ej.ejercicio_id, ej.series || 3, ej.repeticiones || 12, ej.descanso_seg || 60, idx],
        );
      }
    }

    await client.query('COMMIT');
    logger.info('Rutina creada con éxito', { rutinaId: rutina.id, usuarioId: usuario_id });
    return rutina;
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Error al crear rutina (rollback)', { error: error.message });
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Elimina una rutina del usuario (verifica propiedad). @returns {Promise<boolean>}
 */
async function deleteRoutine(rutinaId, usuarioId) {
  const res = await query(
    `DELETE FROM rutinas WHERE id = $1 AND usuario_id = $2`,
    [rutinaId, usuarioId],
  );
  return res.rowCount > 0;
}

module.exports = {
  getUserRoutines,
  createRoutine,
  deleteRoutine,
};
