/**
 * @file services/ai-service/src/services/fitnessContextClient.js
 * @description Cliente inter-servicios para obtener el perfil y progreso físico del usuario desde fitness-service.
 */

'use strict';

const env                   = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:fitnessContextClient');

/**
 * Consulta fitness-service vía M2M para extraer las métricas corporales y rutinas del usuario.
 *
 * @param {string} userId
 * @returns {Promise<object>} Contexto consolidado o estructura vacía por defecto si falla
 */
async function getUserFitnessContext(userId) {
  try {
    const url = `${env.FITNESS_SERVICE_INTERNAL_URL}/api/v1/internal/user-context?userId=${encodeURIComponent(userId)}`;
    const controller = new AbortController();
    const timeoutId  = setTimeout(() => controller.abort(), env.INTER_SERVICE_TIMEOUT_MS || 4000);

    const response = await fetch(url, {
      method:  'GET',
      headers: {
        'x-inter-service-secret': env.INTER_SERVICE_SECRET,
        'Accept':                 'application/json',
      },
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (response.status === 200) {
      const { data } = await response.json();
      logger.debug('Contexto de fitness obtenido exitosamente', { userId });
      return data || {};
    }

    logger.warn('Respuesta no-200 al consultar fitness-service para contexto IA', { status: response.status });
    return {};
  } catch (err) {
    logger.warn('Fallo o timeout obteniendo contexto de fitness (continuando con prompt base)', {
      userId,
      url: `${env.FITNESS_SERVICE_INTERNAL_URL}/api/v1/internal/user-context`,
      errorName: err.name,   // AbortError = timeout | TypeError/ENOTFOUND = URL mala/inalcanzable
      errorCode: err.cause?.code,
      error: err.message,
    });
    return {};
  }
}

/**
 * Resuelve imágenes/videos reales de wger para una lista de nombres de ejercicios,
 * vía M2M contra fitness-service (que consulta catalogo_ejercicios). Best-effort:
 * ante cualquier fallo devuelve {} y la rutina se entrega sin imágenes.
 *
 * @param {string[]} names
 * @returns {Promise<Object<string, {id_wger:number, nombre:string, imagen_url:string, video_url:string, thumbnail_url:string}>>}
 */
async function resolveExerciseImages(names) {
  if (!Array.isArray(names) || names.length === 0) return {};
  try {
    const url = `${env.FITNESS_SERVICE_INTERNAL_URL}/api/v1/internal/exercises/images`;
    const controller = new AbortController();
    const timeoutId  = setTimeout(() => controller.abort(), env.INTER_SERVICE_TIMEOUT_MS || 4000);

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'x-inter-service-secret': env.INTER_SERVICE_SECRET,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({ names: names.slice(0, 80) }),
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (response.status === 200) {
      const { data } = await response.json();
      return data || {};
    }
    logger.warn('Respuesta no-200 al resolver imágenes de ejercicios', { status: response.status });
    return {};
  } catch (err) {
    logger.warn('Fallo o timeout resolviendo imágenes de ejercicios (rutina sin imágenes)', {
      url: `${env.FITNESS_SERVICE_INTERNAL_URL}/api/v1/internal/exercises/images`,
      errorName: err.name,   // AbortError = timeout | TypeError/ENOTFOUND = URL mala/inalcanzable
      errorCode: err.cause?.code,
      error: err.message,
    });
    return {};
  }
}

module.exports = { getUserFitnessContext, resolveExerciseImages };
