/**
 * @file services/fitness-service/src/models/exerciseModel.js
 * @description Capa de datos para el catálogo de ejercicios (ejercicios) con caché en Redis y paginación.
 */

'use strict';

const { getSupabaseClient } = require('../config/database');
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

  const db = getSupabaseClient();
  let query = db
    .from('ejercicios')
    .select('*', { count: 'exact' });

  // Manejar filtros que pueden venir como string simple o como array (gracias a HPP whitelist)
  if (muscleGroup) {
    const arr = Array.isArray(muscleGroup) ? muscleGroup : [muscleGroup];
    query = query.in('grupo_muscular', arr);
  }
  if (difficulty) {
    const arr = Array.isArray(difficulty) ? difficulty : [difficulty];
    query = query.in('dificultad', arr);
  }
  if (equipment) {
    const arr = Array.isArray(equipment) ? equipment : [equipment];
    query = query.in('equipamiento', arr);
  }

  query = query
    .order('nombre', { ascending: true })
    .range(offset, offset + sizeNum - 1);

  const { data, count, error } = await query;

  if (error) {
    logger.error('Error consultando tabla ejercicios en Supabase', { error: error.message });
    throw error;
  }

  const result = {
    exercises: data || [],
    total:     count || 0,
    page:      pageNum,
    pageSize:  sizeNum,
    totalPages: Math.ceil((count || 0) / sizeNum),
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
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('ejercicios')
    .select('*')
    .eq('id', exerciseId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

module.exports = {
  getExercises,
  getExerciseById,
};
