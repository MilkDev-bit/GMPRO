/**
 * @file services/fitness-service/src/models/progressModel.js
 * @description Capa de datos para registro de progreso físico, antropometría y bitácora de entrenamiento.
 */

'use strict';

const { getSupabaseClient }   = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:progressModel');

/**
 * Obtiene el historial de mediciones físicas del usuario.
 *
 * @param {string} usuarioId
 * @param {number} [limit=20]
 * @returns {Promise<object[]>}
 */
async function getPhysicalProgress(usuarioId, limit = 20) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('progreso_fisico')
    .select('*')
    .eq('usuario_id', usuarioId)
    .order('fecha_medicion', { ascending: false })
    .limit(limit);

  if (error) {
    logger.error('Error consultando progreso_fisico', { usuarioId, error: error.message });
    throw error;
  }
  return data || [];
}

/**
 * Registra una nueva medición física (peso, grasa corporal, masa muscular, medidas).
 *
 * @param {object} logData
 * @param {string} logData.usuario_id
 * @param {number} logData.peso_kg
 * @param {number} [logData.porcentaje_grasa]
 * @param {number} [logData.masa_muscular_kg]
 * @param {object} [logData.medidas] - { pecho, cintura, cadera, brazos, piernas } en cm
 * @param {string} [logData.notas]
 * @returns {Promise<object>}
 */
async function recordPhysicalProgress({
  usuario_id,
  peso_kg,
  porcentaje_grasa = null,
  masa_muscular_kg = null,
  medidas = null,
  notas = null,
}) {
  const db    = getSupabaseClient();
  const ahora = new Date().toISOString();

  const { data, error } = await db
    .from('progreso_fisico')
    .insert({
      usuario_id,
      peso_kg,
      porcentaje_grasa,
      masa_muscular_kg,
      medidas:        medidas ? JSON.stringify(medidas) : null,
      notas,
      fecha_medicion: ahora,
    })
    .select('*')
    .single();

  if (error) {
    logger.error('Error insertando registro en progreso_fisico', { error: error.message });
    throw error;
  }

  logger.info('Medición de progreso guardada', { id: data.id, usuarioId: usuario_id, peso_kg });
  return data;
}

/**
 * Obtiene un resumen consolidado para el contexto interno de IA (ai-service).
 * Incluye últimas 5 mediciones, últimas rutinas activas y nivel general.
 *
 * @param {string} usuarioId
 * @returns {Promise<object>}
 */
async function getUserContextSummary(usuarioId) {
  const db = getSupabaseClient();

  // Ejecutar en paralelo para baja latencia
  const [progressRes, routinesRes] = await Promise.all([
    db.from('progreso_fisico').select('*').eq('usuario_id', usuarioId).order('fecha_medicion', { ascending: false }).limit(5),
    db.from('rutinas').select('*, rutina_ejercicios(*, ejercicios(nombre, grupo_muscular))').eq('usuario_id', usuarioId).order('creado_at', { ascending: false }).limit(3),
  ]);

  return {
    usuario_id:       usuarioId,
    ultimas_mediciones: progressRes.data || [],
    rutinas_activas:  routinesRes.data || [],
    generado_en:      new Date().toISOString(),
  };
}

module.exports = {
  getPhysicalProgress,
  recordPhysicalProgress,
  getUserContextSummary,
};
