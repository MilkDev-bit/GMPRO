/**
 * @file services/fitness-service/src/models/exerciseModel.js
 * @description Capa de datos para el catálogo de ejercicios (ejercicios) con caché en Redis y paginación.
 */

'use strict';

const { query } = require('../config/database');   // pg directo (svc_fitness)
const env                   = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:exerciseModel');

/**
 * Consulta el catálogo de ejercicios con filtros, paginación y caché en Redis.
 *
 * @param {object} params
 * @param {string|string[]} [params.muscleGroup] - Filtro de grupo muscular
 * @param {string|string[]} [params.difficulty]  - 'beginner' | 'intermediate' | 'advanced'
 * @param {string|string[]} [params.equipment]   - 'dumbbell' | 'barbell' | 'machine' | 'bodyweight'
 * @param {number} [params.page=1]
 * @param {number} [params.pageSize=20]
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<{ exercises: object[], total: number, page: number, pageSize: number }>}
 */
async function getExercises({
  muscleGroup,
  difficulty,
  equipment,
  page = 1,
  pageSize = env.DEFAULT_PAGE_SIZE,
}, redisClient = null) {
  const pageNum  = Math.max(1, parseInt(page, 10) || 1);
  const sizeNum  = Math.min(env.MAX_PAGE_SIZE, Math.max(1, parseInt(pageSize, 10) || env.DEFAULT_PAGE_SIZE));
  const offset   = (pageNum - 1) * sizeNum;

  // Clave única de caché normalizada
  const cacheKey = `fitness:exercises:catalog:${JSON.stringify({ muscleGroup, difficulty, equipment, pageNum, sizeNum })}`;

  if (redisClient) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        logger.debug('Catálogo de ejercicios obtenido desde caché Redis', { cacheKey });
        return JSON.parse(cached);
      }
    } catch (cacheErr) {
      logger.warn('Error leyendo caché de ejercicios en Redis', { error: cacheErr.message });
    }
  }

  // Filtros dinámicos (pueden venir como string o array por HPP whitelist) → = ANY($n).
  const conds = [];
  const params = [];
  let p = 1;
  if (muscleGroup) { params.push(Array.isArray(muscleGroup) ? muscleGroup : [muscleGroup]); conds.push(`grupo_muscular = ANY($${p++})`); }
  if (difficulty)  { params.push(Array.isArray(difficulty)  ? difficulty  : [difficulty]);  conds.push(`dificultad = ANY($${p++})`); }
  if (equipment)   { params.push(Array.isArray(equipment)   ? equipment   : [equipment]);   conds.push(`equipamiento = ANY($${p++})`); }
  const whereClause = conds.length ? `WHERE ${conds.join(' AND ')}` : '';

  let total, data;
  try {
    const cnt = await query(`SELECT count(*)::int AS total FROM ejercicios ${whereClause}`, params);
    total = cnt.rows[0].total;
    const rowsRes = await query(
      `SELECT * FROM ejercicios ${whereClause} ORDER BY nombre ASC LIMIT $${p} OFFSET $${p + 1}`,
      [...params, sizeNum, offset],
    );
    data = rowsRes.rows;
  } catch (error) {
    logger.error('Error consultando tabla ejercicios', { error: error.message });
    throw error;
  }

  const result = {
    exercises:  data,
    total,
    page:       pageNum,
    pageSize:   sizeNum,
    totalPages: Math.ceil(total / sizeNum),
  };

  if (redisClient) {
    try {
      await redisClient.setex(cacheKey, env.EXERCISE_CATALOG_CACHE_TTL || 3600, JSON.stringify(result));
    } catch (cacheErr) {
      logger.warn('Error escribiendo en caché de Redis para ejercicios', { error: cacheErr.message });
    }
  }

  return result;
}

/**
 * Obtiene un ejercicio específico por su ID o UUID.
 *
 * @param {string} exerciseId
 * @returns {Promise<object|null>}
 */
async function getExerciseById(exerciseId) {
  const { rows } = await query(`SELECT * FROM ejercicios WHERE id = $1 LIMIT 1`, [exerciseId]);
  return rows[0] || null;
}

module.exports = {
  getExercises,
  getExerciseById,
};
