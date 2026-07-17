/**
 * @file services/ai-service/src/controllers/recommendationController.js
 * @description Controlador para generación de rutinas y planes de nutrición estructurados (JSON).
 * La IA genera obligatoriamente musculos_primarios y musculos_secundarios por ejercicio
 * siguiendo el catálogo estándar NSCA/ACSM, habilitando el mapa anatómico interactivo en la app.
 */

'use strict';

const sanitizerService        = require('../services/sanitizerService');
const fitnessContextClient    = require('../services/fitnessContextClient');
const llmClientService        = require('../services/llmClientService');
const env                     = require('../config/environment');
const { VALID_MUSCLE_KEYS }   = require('../constants/muscleGroups');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:recommendationController');

/**
 * POST /api/v1/recommendations/routine
 * Genera una rutina de entrenamiento personalizada en formato JSON estructurado
 * con datos anatómicos completos por ejercicio para el mapa muscular interactivo.
 */
async function generateRoutinePlan(req, res, next) {
  try {
    const usuarioId = req.user.id;
    const {
      objetivo       = 'hipertrofia',
      diasPorSemana  = 4,
      nivel          = 'intermedio',
      lesiones       = 'ninguna',
    } = req.body;

    // Sanitizar campos libres del usuario antes de inyectarlos al prompt
    const checkLesiones = sanitizerService.sanitizeUserPrompt(lesiones);
    if (!checkLesiones.isValid) {
      return res.status(400).json({ success: false, data: null, error: checkLesiones.rejectionReason });
    }

    const userContext = await fitnessContextClient.getUserFitnessContext(usuarioId);

    // ── CATÁLOGO INYECTADO EN EL PROMPT ──────────────────────────────────────
    // Se limita a 80 claves para no saturar la ventana de contexto del LLM
    const muscleSample = VALID_MUSCLE_KEYS.slice(0, 80).join(' | ');

    const systemPrompt = `${env.AI_SYSTEM_PERSONA}

## MODO: Científico del Deporte y Entrenador en Jefe con Mapeo Anatómico

Tu objetivo es generar una rutina de entrenamiento personalizada ESTRICTAMENTE en el siguiente formato JSON.
**REGLA CRÍTICA**: Para CADA ejercicio debes incluir:
  - "musculos_primarios": Array de músculos principales activados (≥1 músculo).
  - "musculos_secundarios": Array de músculos secundarios o estabilizadores (puede ser [] si no aplica).
  - "ejercicio_id": Identificador único en formato "wger-<número_3_digitos>".
  - "video_url": URL de ejemplo en https://wger.de/media/exercise-videos/video.mp4 (puedes inventar un path válido).

### CLAVES VÁLIDAS DE MÚSCULOS (usa SOLO estas, sin inventar nuevas):
${muscleSample}

### ESQUEMA JSON OBLIGATORIO:
{
  "nombre": "String — Nombre motivador del plan",
  "descripcion": "String — Resumen fisiológico y objetivo",
  "nivel": "<nivel>",
  "objetivo": "<objetivo>",
  "dias": [
    {
      "dia": "Día 1 — Pecho y Tríceps",
      "enfoque_muscular": ["pectoral_mayor_esternal", "triceps_braquial"],
      "ejercicios": [
        {
          "ejercicio_id": "wger-001",
          "nombre": "Press de Banca con Barra",
          "musculos_primarios": ["pectoral_mayor_esternal", "pectoral_mayor_superior"],
          "musculos_secundarios": ["triceps_braquial", "deltoides_anterior"],
          "series": 4,
          "repeticiones": "8-10",
          "descanso_seg": 90,
          "notas": "Controlar la fase excéntrica. Codos a 45°.",
          "video_url": "https://wger.de/media/exercise-videos/bench-press.mp4"
        }
      ]
    }
  ]
}

No devuelvas ningún texto, comentario ni markdown fuera del bloque JSON puro. Tu respuesta comienza con { y termina con }.`;

    const userPrompt = `Genera un plan de ${diasPorSemana} días por semana enfocado en ${objetivo} para nivel ${nivel}.
Consideraciones de lesiones/restricciones: ${checkLesiones.sanitized}
Datos corporales previos del socio: ${JSON.stringify(userContext.ultimas_mediciones || [])}`;

    logger.info('Generando plan de rutina IA con datos anatómicos', { usuarioId, objetivo, diasPorSemana, nivel });

    const rawJsonString = await llmClientService.generateStructuredContent(systemPrompt, userPrompt, true);

    let planStructured;
    try {
      planStructured = JSON.parse(rawJsonString);
    } catch (parseErr) {
      logger.warn('Fallo al parsear respuesta IA, retornando como texto crudo', { error: parseErr.message });
      planStructured = { nombre: `Plan ${objetivo}`, rawContent: rawJsonString };
    }

    // ── POST-PROCESO: Validar y normalizar claves musculares ──────────────────
    // Si el LLM inventó una clave no existente, se elimina en silencio para
    // evitar que el frontend intente renderizar un músculo que no existe en el SVG.
    if (planStructured.dias && Array.isArray(planStructured.dias)) {
      for (const dia of planStructured.dias) {
        if (!Array.isArray(dia.ejercicios)) continue;
        for (const ej of dia.ejercicios) {
          ej.musculos_primarios = _filterValidMuscles(ej.musculos_primarios);
          ej.musculos_secundarios = _filterValidMuscles(ej.musculos_secundarios);
          // Garantizar ejercicio_id siempre presente
          if (!ej.ejercicio_id) {
            ej.ejercicio_id = `wger-${Math.floor(Math.random() * 900 + 100)}`;
          }
        }
      }
    }

    logger.info('Plan de rutina con mapeo anatómico generado exitosamente', { usuarioId });

    return res.status(200).json({
      success: true,
      data:    planStructured,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/recommendations/diet
 * Genera un plan de nutrición y macros personalizado en formato JSON estructurado
 * con alimentos y códigos de barras de Open Food Facts.
 */
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

    const systemPrompt = `${env.AI_SYSTEM_PERSONA}

## MODO: Nutricionista Deportivo IA & Coach de Rendimiento (Open Food Facts)

Tu objetivo es generar un plan nutricional personalizado con desglose de macronutrientes ESTRICTAMENTE en el siguiente formato JSON.
**REGLA CRÍTICA**: Los alimentos sugeridos en cada comida deben asociarse con códigos de barras reales o estándares precargados de Open Food Facts (por ejemplo: avena, pechuga de pollo, arroz integral, atún, proteína whey, huevo).

### ESQUEMA JSON OBLIGATORIO:
{
  "nombre": "String — Nombre motivador del plan nutricional",
  "descripcion": "String — Estrategia calórica y reparto de macros",
  "objetivo": "<objetivo>",
  "calorias_meta": 2600,
  "proteinas_meta_g": 180,
  "carbohidratos_meta_g": 300,
  "grasas_meta_g": 75,
  "agua_meta_ml": 3500,
  "comidas": [
    {
      "id": "meal_desayuno",
      "tipo": "desayuno",
      "nombre": "Desayuno Energético Hipertrofia",
      "hora_sugerida": "08:00 AM",
      "calorias": 650,
      "proteinas": 42,
      "carbohidratos": 78,
      "grasas": 18,
      "alimentos": [
        {
          "codigo_barras": "7501008012345",
          "nombre": "Avena Integral Quaker",
          "marca": "Quaker",
          "porcion_g": 80,
          "calorias_100g": 370,
          "proteinas_100g": 13.5,
          "carbohidratos_100g": 66.0,
          "grasas_100g": 7.0,
          "es_open_food_facts": true
        },
        {
          "codigo_barras": "7501111122222",
          "nombre": "Claras de Huevo Líquidas y Huevos Enteros",
          "marca": "San Juan",
          "porcion_g": 200,
          "calorias_100g": 140,
          "proteinas_100g": 13.0,
          "carbohidratos_100g": 1.1,
          "grasas_100g": 9.5,
          "es_open_food_facts": true
        }
      ]
    }
  ]
}

No devuelvas ningún texto, comentario ni markdown fuera del bloque JSON puro. Tu respuesta comienza con { y termina con }.`;

    const userPrompt = `Genera un plan de nutrición para objetivo ${objetivo}, peso ${pesoKg}kg, estatura ${estaturaCm}cm, actividad ${actividad}.
Restricciones alimentarias: ${checkRestricciones.sanitized}`;

    logger.info('Generando plan nutricional IA con Open Food Facts', { usuarioId, objetivo, pesoKg });

    const rawJsonString = await llmClientService.generateStructuredContent(systemPrompt, userPrompt, true);

    let planStructured;
    try {
      planStructured = JSON.parse(rawJsonString);
    } catch (parseErr) {
      logger.warn('Fallo al parsear respuesta IA nutrición, retornando fallback', { error: parseErr.message });
      planStructured = { nombre: `Plan ${objetivo}`, rawContent: rawJsonString };
    }

    return res.status(200).json({
      success: true,
      data:    planStructured,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * Filtra un array de claves musculares, retornando solo las que existen en el catálogo NSCA/ACSM.
 * @param {any} arr
 * @returns {string[]}
 */
function _filterValidMuscles(arr) {
  if (!Array.isArray(arr)) return [];
  return arr.filter((key) => typeof key === 'string' && VALID_MUSCLE_KEYS.includes(key));
}

module.exports = { generateRoutinePlan, generateDietPlan };

