/**
 * @file services/ai-service/src/services/modelHealthCheck.js
 * @description Verifica al arrancar que los modelos configurados EXISTEN.
 *
 * POR QUÉ ESTE MÓDULO:
 *   Google retira modelos con relativa frecuencia y sin avisar en el
 *   código: `gemini-2.0-flash` se apagó el 1 de junio de 2026,
 *   `gemini-1.5-*` y `text-embedding-004` antes. Cuando eso pasa, el
 *   servicio arranca sin problemas y falla con un 404 en CADA petición
 *   de usuario. El error se ve en el cliente, no en el despliegue: te
 *   enteras por un ticket de soporte, no por el pipeline.
 *
 *   Esta comprobación convierte ese fallo silencioso y diferido en un
 *   aviso ruidoso en el arranque, con la lista de modelos que la clave
 *   sí tiene disponibles.
 *
 * COMPORTAMIENTO:
 *   - En producción NO tumba el servicio: un fallo de red al consultar
 *     el catálogo no debe impedir el arranque. Loguea a nivel error.
 *   - En desarrollo loguea el aviso igual de visible.
 *   - Es best-effort y con timeout corto: nunca retrasa el arranque más
 *     de unos segundos.
 */

'use strict';

const env = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:modelHealthCheck');

const CHECK_TIMEOUT_MS = parseInt(process.env.MODEL_CHECK_TIMEOUT_MS || '5000', 10);

/**
 * Lista los modelos disponibles para la clave configurada.
 * @returns {Promise<string[]|null>} null si no se pudo consultar.
 */
async function listGeminiModels() {
  const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${env.GEMINI_API_KEY}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CHECK_TIMEOUT_MS);

  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      logger.warn('No se pudo listar modelos de Gemini', { status: res.status });
      return null;
    }
    const data = await res.json();
    return (data.models || [])
      .filter((m) => (m.supportedGenerationMethods || []).includes('generateContent'))
      .map((m) => m.name.replace(/^models\//, ''));
  } catch (err) {
    logger.warn('Consulta del catálogo de modelos falló', { error: err.message });
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function listOpenAIModels() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CHECK_TIMEOUT_MS);

  try {
    const res = await fetch('https://api.openai.com/v1/models', {
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      signal: controller.signal,
    });
    if (!res.ok) {
      logger.warn('No se pudo listar modelos de OpenAI', { status: res.status });
      return null;
    }
    const data = await res.json();
    return (data.data || []).map((m) => m.id);
  } catch (err) {
    logger.warn('Consulta del catálogo de OpenAI falló', { error: err.message });
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Comprueba los modelos configurados contra el catálogo real del proveedor.
 * @returns {Promise<{ok: boolean, missing: string[], available: string[]}>}
 */
async function verifyConfiguredModels() {
  const provider = env.AI_PROVIDER;

  const configured =
    provider === 'gemini'
      ? [env.GEMINI_MODEL, env.GEMINI_MODEL_PRO]
      : [env.OPENAI_MODEL, env.OPENAI_MODEL_PRO];

  const available =
    provider === 'gemini' ? await listGeminiModels() : await listOpenAIModels();

  // Sin catálogo no podemos afirmar nada: mejor callar que dar un falso
  // positivo que haga desconfiar de la comprobación.
  if (!available) {
    logger.info('Verificación de modelos omitida (catálogo no disponible)', { provider });
    return { ok: true, missing: [], available: [] };
  }

  const missing = configured.filter((m) => m && !available.includes(m));

  if (missing.length > 0) {
    // Sugerir alternativas de la misma familia ayuda a resolverlo sin
    // salir de los logs.
    const suggestions = available
      .filter((m) => /flash|mini|lite/i.test(m))
      .slice(0, 6);

    logger.error(
      'MODELOS CONFIGURADOS NO DISPONIBLES — el servicio devolverá 404 en cada petición',
      {
        provider,
        missing,
        sugerencias: suggestions,
        accion: 'Actualiza GEMINI_MODEL / GEMINI_MODEL_PRO en el .env y reinicia',
      },
    );
    return { ok: false, missing, available };
  }

  logger.info('Modelos verificados contra el proveedor', { provider, configured });
  return { ok: true, missing: [], available };
}

module.exports = { verifyConfiguredModels, listGeminiModels, listOpenAIModels };
