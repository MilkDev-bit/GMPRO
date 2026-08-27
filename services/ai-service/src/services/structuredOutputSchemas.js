/**
 * @file services/ai-service/src/services/structuredOutputSchemas.js
 * @description Esquemas de SALIDA ESTRUCTURADA para forzar al LLM a devolver JSON
 * válido y, sobre todo, claves musculares del catálogo mediante `enum` (Eje 1 + Eje 4).
 *
 * BENEFICIO DOBLE:
 *   • Anti-alucinación: con `enum` de músculos, el modelo NO puede emitir una clave
 *     inexistente (se elimina de raíz el problema del Eje 1 en origen).
 *   • Ahorro de tokens/latencia: al declarar el esquema por API ya no hace falta
 *     inyectar la lista de 43 músculos ni el ejemplo JSON gigante en el prompt de
 *     texto (Eje 4). El System Prompt se reduce a la persona + reglas breves.
 *
 * Gemini  → generationConfig.responseSchema (+ responseMimeType 'application/json').
 * OpenAI  → response_format { type:'json_schema', json_schema:{ strict:true, schema } }.
 */

'use strict';

const { VALID_MUSCLE_KEYS } = require('../constants/muscleGroups');

// ── GEMINI: rutina con enum de músculos ──────────────────────────────────────
function geminiRoutineSchema() {
  const muscleArray = {
    type: 'ARRAY',
    items: { type: 'STRING', enum: VALID_MUSCLE_KEYS },
  };
  return {
    type: 'OBJECT',
    properties: {
      nombre:      { type: 'STRING' },
      descripcion: { type: 'STRING' },
      nivel:       { type: 'STRING' },
      objetivo:    { type: 'STRING' },
      dias: {
        type: 'ARRAY',
        items: {
          type: 'OBJECT',
          properties: {
            dia:              { type: 'STRING' },
            enfoque_muscular: muscleArray,
            ejercicios: {
              type: 'ARRAY',
              items: {
                type: 'OBJECT',
                properties: {
                  ejercicio_id:        { type: 'STRING' },
                  nombre:              { type: 'STRING' },
                  musculos_primarios:  muscleArray,
                  musculos_secundarios: muscleArray,
                  series:              { type: 'INTEGER' },
                  repeticiones:        { type: 'STRING' },
                  descanso_seg:        { type: 'INTEGER' },
                  notas:               { type: 'STRING' },
                },
                required: ['ejercicio_id', 'nombre', 'musculos_primarios', 'series', 'repeticiones'],
              },
            },
          },
          required: ['dia', 'enfoque_muscular', 'ejercicios'],
        },
      },
    },
    required: ['nombre', 'objetivo', 'dias'],
  };
}

// ── GEMINI: dieta con macros numéricos estrictos ─────────────────────────────
function geminiDietSchema() {
  const foodSchema = {
    type: 'OBJECT',
    properties: {
      codigo_barras:      { type: 'STRING' },
      nombre:             { type: 'STRING' },
      marca:              { type: 'STRING' },
      porcion_g:          { type: 'NUMBER' },
      calorias_100g:      { type: 'NUMBER' },
      proteinas_100g:     { type: 'NUMBER' },
      carbohidratos_100g: { type: 'NUMBER' },
      grasas_100g:        { type: 'NUMBER' },
    },
    required: ['nombre', 'porcion_g', 'calorias_100g', 'proteinas_100g', 'carbohidratos_100g', 'grasas_100g'],
  };
  return {
    type: 'OBJECT',
    properties: {
      nombre:               { type: 'STRING' },
      descripcion:          { type: 'STRING' },
      objetivo:             { type: 'STRING' },
      calorias_meta:        { type: 'INTEGER' },
      proteinas_meta_g:     { type: 'INTEGER' },
      carbohidratos_meta_g: { type: 'INTEGER' },
      grasas_meta_g:        { type: 'INTEGER' },
      agua_meta_ml:         { type: 'INTEGER' },
      comidas: {
        type: 'ARRAY',
        items: {
          type: 'OBJECT',
          properties: {
            id:            { type: 'STRING' },
            tipo:          { type: 'STRING' },
            nombre:        { type: 'STRING' },
            hora_sugerida: { type: 'STRING' },
            calorias:      { type: 'INTEGER' },
            proteinas:     { type: 'NUMBER' },
            carbohidratos: { type: 'NUMBER' },
            grasas:        { type: 'NUMBER' },
            alimentos:     { type: 'ARRAY', items: foodSchema },
            // Pasos de preparación de la receta (breves, en orden). Lo que faltaba:
            // antes solo se daban ingredientes, no cómo cocinarlos.
            preparacion:   { type: 'ARRAY', items: { type: 'STRING' } },
          },
          required: ['tipo', 'calorias', 'proteinas', 'carbohidratos', 'grasas', 'alimentos', 'preparacion'],
        },
      },
    },
    required: ['calorias_meta', 'proteinas_meta_g', 'carbohidratos_meta_g', 'grasas_meta_g', 'comidas'],
  };
}

/**
 * Convierte un esquema Gemini (MAYÚSCULAS) al dialecto JSON Schema de OpenAI
 * (tipos en minúscula, `additionalProperties:false`). Reutiliza la misma fuente.
 */
function toOpenAiJsonSchema(node) {
  if (Array.isArray(node)) return node.map(toOpenAiJsonSchema);
  if (node && typeof node === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(node)) {
      if (k === 'type' && typeof v === 'string') {
        out.type = v.toLowerCase() === 'integer' ? 'integer' : v.toLowerCase();
      } else {
        out[k] = toOpenAiJsonSchema(v);
      }
    }
    if (out.type === 'object' && out.properties && !('additionalProperties' in out)) {
      out.additionalProperties = false;
    }
    return out;
  }
  return node;
}

module.exports = {
  geminiRoutineSchema,
  geminiDietSchema,
  openaiRoutineSchema: () => ({ name: 'rutina_gympro', strict: true, schema: toOpenAiJsonSchema(geminiRoutineSchema()) }),
  openaiDietSchema:    () => ({ name: 'dieta_gympro',  strict: true, schema: toOpenAiJsonSchema(geminiDietSchema()) }),
};
