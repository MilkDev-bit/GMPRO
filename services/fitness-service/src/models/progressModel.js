/**
 * @file services/fitness-service/src/models/progressModel.js
 * @description Capa de datos para progreso físico y contexto de IA.
 * Mínimo privilegio (CLD-1): pg con rol svc_fitness, SQL parametrizado.
 */

'use strict';

const { query }               = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:progressModel');

/** Historial de mediciones físicas del usuario. @returns {Promise<object[]>} */
async function getPhysicalProgress(usuarioId, limit = 20) {
  try {
    const { rows } = await query(
      `SELECT * FROM progreso_fisico
       WHERE usuario_id = $1 ORDER BY fecha_medicion DESC LIMIT $2`,
      [usuarioId, limit],
    );
    return rows;
  } catch (error) {
    logger.error('Error consultando progreso_fisico', { usuarioId, error: error.message });
    throw error;
  }
}

/** Registra una medición física. @returns {Promise<object>} */
async function recordPhysicalProgress({
  usuario_id,
  peso_kg,
  porcentaje_grasa = null,
  masa_muscular_kg = null,
  medidas = null,
  notas = null,
}) {
  try {
    const { rows } = await query(
      `INSERT INTO progreso_fisico
         (usuario_id, peso_kg, porcentaje_grasa, masa_muscular_kg, medidas, notas, fecha_medicion)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       RETURNING *`,
      [usuario_id, peso_kg, porcentaje_grasa, masa_muscular_kg,
       medidas ? JSON.stringify(medidas) : null, notas, new Date().toISOString()],
    );
    logger.info('Medición de progreso guardada', { id: rows[0].id, usuarioId: usuario_id, peso_kg });
    return rows[0];
  } catch (error) {
    logger.error('Error insertando registro en progreso_fisico', { error: error.message });
    throw error;
  }
}

/**
 * Resumen consolidado para el contexto de IA: últimas 5 mediciones + últimas 3 rutinas
 * (con sus ejercicios acotados a nombre/grupo_muscular).
 * @returns {Promise<object>}
 */
async function getUserContextSummary(usuarioId) {
  const [progressRes, routinesRes] = await Promise.all([
    query(
      `SELECT * FROM progreso_fisico
       WHERE usuario_id = $1 ORDER BY fecha_medicion DESC LIMIT 5`,
      [usuarioId],
    ),
    query(
      `SELECT r.*,
         COALESCE((
           SELECT jsonb_agg(
                    jsonb_build_object(
                      'id', re.id, 'series', re.series, 'repeticiones', re.repeticiones,
                      'descanso_seg', re.descanso_seg, 'orden', re.orden,
                      'ejercicios', jsonb_build_object('nombre', e.nombre, 'grupo_muscular', e.grupo_muscular)
                    ) ORDER BY re.orden)
           FROM rutina_ejercicios re
           JOIN ejercicios e ON e.id = re.ejercicio_id
           WHERE re.rutina_id = r.id
         ), '[]'::jsonb) AS rutina_ejercicios
       FROM rutinas r
       WHERE r.usuario_id = $1
       ORDER BY r.creado_at DESC LIMIT 3`,
      [usuarioId],
    ),
  ]);

  return {
    usuario_id:         usuarioId,
    ultimas_mediciones: progressRes.rows,
    rutinas_activas:    routinesRes.rows,
    generado_en:        new Date().toISOString(),
  };
}

module.exports = {
  getPhysicalProgress,
  recordPhysicalProgress,
  getUserContextSummary,
};
