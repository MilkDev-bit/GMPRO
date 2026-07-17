/**
 * @file services/ai-service/src/controllers/recommendationController.js
 * @description Generación de rutinas y planes de nutrición estructurados (JSON) con:
 *   1. Salida estructurada NATIVA del LLM (responseSchema Gemini / json_schema OpenAI)
 *      → el modelo no puede inventar claves musculares ni romper el esquema, y el
 *        System Prompt queda esbelto (sin lista de 43 músculos ni ejemplo JSON gigante).
 *   2. Tubería de validación secuencial:
 *        rutina  → muscleValidator.repairRoutinePlan
 *        dieta   → macroSanitizer.validateAndReconcile → foodReconciliationService
 *   3. Caché Redis (hash del perfil, TTL 24h) para latencia < 5ms y ahorro de tokens.
 *
 * El contrato con el frontend NO cambia: { success, data, error }. Los planes
 * incorporan metadatos no intrusivos (_macros_check, _food_check, _meta) que la UI
 * puede ignorar sin romperse.
 */

'use strict';

const crypto                  = require('crypto');
const sanitizerService        = require('../services/sanitizerService');
const fitnessContextClient    = require('../services/fitnessContextClient');
const llmClientService        = require('../services/llmClientService');
const muscleValidator         = require('../services/muscleValidator');
const macroSanitizer          = require('../services/macroSanitizer');
const foodReconciliation      = require('../services/foodReconciliationService');
const foodCatalogClient       = require('../services/foodCatalogClient');
const schemas                 = require('../services/structuredOutputSchemas');
const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:recommendationController');

const CACHE_TTL = env.AI_RECOMMENDATION_CACHE_TTL || 86_400; // 24h por defecto
const IS_GEMINI = env.AI_PROVIDER === 'gemini';

// ── Helpers de caché Redis ────────────────────────────────────────────────────
/**
 * Construye una clave de caché determinista a partir del perfil/params del usuario.
 * @param {string} kind - 'routine' | 'diet'
 * @param {string} usuarioId
 * @param {object} params - Parámetros normalizados que determinan el plan.
 */
function buildCacheKey(kind, usuarioId, params) {
  // Orden estable de claves para que el hash no dependa del orden de inserción.
  const stable = JSON.stringify(params, Object.keys(params).sort());
  const hash = crypto.createHash('sha256').update(stable).digest('hex').slice(0, 32);
  return `ai:reco:${kind}:${usuarioId}:${hash}`;
}

async function readCache(redisClient, key) {
  if (!redisClient) return null;
  try {
    const cached = await redisClient.get(key);
    return cached ? JSON.parse(cached) : null;
  } catch (err) {
    logger.warn('Fallo leyendo caché de recomendación en Redis', { key, error: err.message });
    return null;
  }
}

async function writeCache(redisClient, key, value) {
  if (!redisClient) return;
  try {
    await redisClient.setex(key, CACHE_TTL, JSON.stringify(value));
  } catch (err) {
    logger.warn('Fallo escribiendo caché de recomendación en Redis', { key, error: err.message });
  }
}

/** Devuelve las opciones de esquema estructurado según el proveedor activo. */
function schemaOptions(kind) {
  if (kind === 'routine') {
    return IS_GEMINI
      ? { useProModel: true, responseSchema: schemas.geminiRoutineSchema() }
      : { useProModel: true, openaiJsonSchema: schemas.openaiRoutineSchema() };
  }
  return IS_GEMINI
    ? { useProModel: true, responseSchema: schemas.geminiDietSchema() }
    : { useProModel: true, openaiJsonSchema: schemas.openaiDietSchema() };
}

/** Parseo tolerante: intenta rescatar el bloque JSON aunque venga con envoltura. */
function parseLlmJson(raw) {
  try { return JSON.parse(raw); } catch (_) {}
  const start = raw.indexOf('{');
  const end   = raw.lastIndexOf('}');
  if (start !== -1 && end > start) {
    try { return JSON.parse(raw.slice(start, end + 1)); } catch (_) {}
  }
  return null;
}

// ── POST /api/v1/recommendations/routine ──────────────────────────────────────
async function generateRoutinePlan(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const {
      objetivo      = 'hipertrofia',
      diasPorSemana = 4,
      nivel         = 'intermedio',
      lesiones      = 'ninguna',
    } = req.body;

    const checkLesiones = sanitizerService.sanitizeUserPrompt(lesiones);
    if (!checkLesiones.isValid) {
      return res.status(400).json({ success: false, data: null, error: checkLesiones.rejectionReason });
    }

    // ── Caché: si el mismo perfil ya generó plan, responder al instante ───────
    const cacheKey = buildCacheKey('routine', usuarioId, {
      objetivo, diasPorSemana, nivel, lesiones: checkLesiones.sanitized,
    });
    const cached = await readCache(req.redisClient, cacheKey);
    if (cached) {
      logger.info('Rutina servida desde caché Redis', { usuarioId, cacheKey });
      return res.status(200).json({ success: true, data: cached, error: null });
    }

    const userContext = await fitnessContextClient.getUserFitnessContext(usuarioId);

    // System Prompt ESBELTO: la restricción de esquema/músculos la impone el
    // responseSchema nativo del LLM, no el texto del prompt (ahorro de tokens).
    const systemPrompt = `${env.AI_SYSTEM_PERSONA}

## MODO: Científico del Deporte y Entrenador en Jefe con Mapeo Anatómico
Genera una rutina de entrenamiento personalizada. Para CADA ejercicio incluye
músculos primarios (≥1) y secundarios usando ÚNICAMENTE las claves permitidas por
el esquema, y un ejercicio_id con formato "wger-<número>". Responde solo el JSON
del esquema, sin texto adicional.`;

    const userPrompt = `Plan de ${diasPorSemana} días/semana, objetivo ${objetivo}, nivel ${nivel}.
Lesiones/restricciones: ${checkLesiones.sanitized}
Mediciones recientes del socio: ${JSON.stringify(userContext.ultimas_mediciones || [])}`;

    logger.info('Generando plan de rutina IA (structured output)', { usuarioId, objetivo, diasPorSemana, nivel });

    const rawJsonString = await llmClientService.generateStructuredContent(
      systemPrompt, userPrompt, schemaOptions('routine'),
    );

    const parsed = parseLlmJson(rawJsonString);
    if (!parsed) {
      logger.error('Respuesta de rutina no parseable como JSON', { usuarioId });
      return res.status(502).json({
        success: false, data: null,
        error: 'La IA devolvió una respuesta no válida. Intenta de nuevo.',
      });
    }

    // ── Tubería de validación: músculos (fuzzy-match + invariantes) ───────────
    const { plan, corrections, discarded, droppedExercises } = muscleValidator.repairRoutinePlan(parsed);
    if (corrections.length || discarded.length) {
      logger.info('Rutina auto-corregida por muscleValidator', {
        usuarioId, corrections: corrections.length, discarded: discarded.length, droppedExercises,
      });
    }
    plan._meta = { auto_corregido: corrections.length + discarded.length, generado_en: new Date().toISOString() };

    await writeCache(req.redisClient, cacheKey, plan);

    return res.status(200).json({ success: true, data: plan, error: null });
  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/recommendations/diet ─────────────────────────────────────────
async function generateDietPlan(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const {
      objetivo      = 'hipertrofia',
      pesoKg        = 75,
      estaturaCm    = 175,
      edad          = 25,
      actividad     = 'moderada',
      restricciones = 'ninguna',
    } = req.body;

    const checkRestricciones = sanitizerService.sanitizeUserPrompt(restricciones);
    if (!checkRestricciones.isValid) {
      return res.status(400).json({ success: false, data: null, error: checkRestricciones.rejectionReason });
    }

    // ── Caché por perfil nutricional ──────────────────────────────────────────
    const cacheKey = buildCacheKey('diet', usuarioId, {
      objetivo, pesoKg, estaturaCm, edad, actividad, restricciones: checkRestricciones.sanitized,
    });
    const cached = await readCache(req.redisClient, cacheKey);
    if (cached) {
      logger.info('Dieta servida desde caché Redis', { usuarioId, cacheKey });
      return res.status(200).json({ success: true, data: cached, error: null });
    }

    const systemPrompt = `${env.AI_SYSTEM_PERSONA}

## MODO: Nutricionista Deportivo IA & Coach de Rendimiento (Open Food Facts)
Genera un plan nutricional con desglose de macros conforme al esquema. Asocia cada
alimento a un código de barras de Open Food Facts cuando sea posible. La energía
debe respetar Atwater (proteína 4 kcal/g, carbohidrato 4 kcal/g, grasa 9 kcal/g).
Responde solo el JSON del esquema, sin texto adicional.`;

    const userPrompt = `Objetivo ${objetivo}, peso ${pesoKg}kg, estatura ${estaturaCm}cm, edad ${edad}, actividad ${actividad}.
Restricciones alimentarias: ${checkRestricciones.sanitized}`;

    logger.info('Generando plan nutricional IA (structured output)', { usuarioId, objetivo, pesoKg });

    const rawJsonString = await llmClientService.generateStructuredContent(
      systemPrompt, userPrompt, schemaOptions('diet'),
    );

    const parsed = parseLlmJson(rawJsonString);
    if (!parsed) {
      logger.error('Respuesta de dieta no parseable como JSON', { usuarioId });
      return res.status(502).json({
        success: false, data: null,
        error: 'La IA devolvió una respuesta no válida. Intenta de nuevo.',
      });
    }

    // ── Tubería de validación: 1) macros Atwater, 2) reconciliación de barcodes ─
    const macroResult = macroSanitizer.validateAndReconcile(parsed);
    if (macroResult.corrections.length || macroResult.warnings.length) {
      logger.info('Plan nutricional reconciliado (Atwater)', {
        usuarioId,
        corrections: macroResult.corrections.length,
        warnings: macroResult.warnings.length,
      });
    }

    const foodResult = await foodReconciliation.reconcilePlanFoods(macroResult.plan, {
      lookupByBarcodes: foodCatalogClient.lookupByBarcodes,
      lookupByName:     foodCatalogClient.lookupByName,
      useOpenFoodFacts: true,
    });
    if (foodResult.degraded > 0) {
      logger.info('Barcodes alucinados degradados', {
        usuarioId, verificados: foodResult.verified, degradados: foodResult.degraded,
      });
    }

    const finalPlan = foodResult.plan;
    finalPlan._meta = {
      macros_corregidos: macroResult.corrections.length,
      alimentos_verificados: foodResult.verified,
      alimentos_degradados: foodResult.degraded,
      generado_en: new Date().toISOString(),
    };

    await writeCache(req.redisClient, cacheKey, finalPlan);

    return res.status(200).json({ success: true, data: finalPlan, error: null });
  } catch (err) {
    next(err);
  }
}

module.exports = { generateRoutinePlan, generateDietPlan };
