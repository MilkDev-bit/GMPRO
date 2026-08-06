/**
 * @file services/ai-service/src/services/llmClientService.js
 * @description Cliente unificado para Google Gemini y OpenAI con soporte SSE Streaming y JSON estructurado.
 */

'use strict';

const env                   = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:llmClientService');

/**
 * Genera una respuesta en streaming SSE (Server-Sent Events) hacia el cliente de Express.
 * Transmite token a token con baja latencia en formato event-stream.
 *
 * @param {import('express').Response} res
 * @param {string} systemPrompt - Instrucciones de sistema e información del usuario
 * @param {string} userMessage  - Mensaje ya sanitizado del usuario
 * @param {object[]} [history=[]] - Historial previo de conversación
 * @returns {Promise<void>}
 */
async function generateChatStreamSSE(res, systemPrompt, userMessage, history = []) {
  // Configurar cabeceras SSE HTTP/1.1 de inmediato
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // Deshabilita buffering en Nginx si se usa proxy
  res.flushHeaders();

  const provider = env.AI_PROVIDER;

  try {
    if (provider === 'gemini') {
      await streamGeminiSSE(res, systemPrompt, userMessage, history);
    } else {
      await streamOpenAISSE(res, systemPrompt, userMessage, history);
    }
  } catch (err) {
    logger.error('Error durante streaming SSE al LLM', { provider, error: err.message });
    // Enviar evento de error al cliente SSE si la conexión sigue abierta
    if (!res.writableEnded) {
      res.write(`data: ${JSON.stringify({ error: 'Ocurrió un error procesando tu consulta con Inteligencia Artificial.' })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    }
  }
}

/**
 * Transmisión SSE con Google Gemini REST API (streamGenerateContent?alt=sse)
 */
async function streamGeminiSSE(res, systemPrompt, userMessage, history) {
  const model = env.GEMINI_MODEL || 'gemini-3.5-flash';
  const url   = `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`;

  // Formatear historial al esquema de Gemini ({ role: 'user'|'model', parts: [{ text }] })
  const contents = [];
  for (const msg of history.slice(-env.AI_MAX_CONTEXT_MESSAGES || -20)) {
    contents.push({
      role:  msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: msg.content || '' }],
    });
  }
  contents.push({
    role:  'user',
    parts: [{ text: userMessage }],
  });

  const payload = {
    system_instruction: {
      parts: [{ text: systemPrompt }],
    },
    contents,
    generationConfig: {
      temperature:     env.AI_TEMPERATURE || 0.4,
      maxOutputTokens: env.AI_MAX_OUTPUT_TOKENS || 2048,
    },
  };

  const response = await fetch(url, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(payload),
  });

  if (!response.ok || !response.body) {
    const errText = await response.text().catch(() => 'Sin detalles');
    throw new Error(`Gemini API Error (${response.status}): ${errText}`);
  }

  const reader  = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer    = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || ''; // Guardar línea incompleta en buffer

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const dataStr = line.slice(6).trim();
        if (!dataStr || dataStr === '[DONE]') continue;

        try {
          const jsonChunk = JSON.parse(dataStr);
          const textChunk = jsonChunk.candidates?.[0]?.content?.parts?.[0]?.text;
          if (textChunk) {
            res.write(`data: ${JSON.stringify({ token: textChunk })}\n\n`);
          }
        } catch (parseErr) {
          // Ignorar chunks malformados temporales en streams largos
        }
      }
    }
  }

  res.write('data: [DONE]\n\n');
  res.end();
}

/**
 * Transmisión SSE con OpenAI REST API (/v1/chat/completions con stream: true)
 */
async function streamOpenAISSE(res, systemPrompt, userMessage, history) {
  const model = env.OPENAI_MODEL || 'gpt-4o-mini';
  const url   = 'https://api.openai.com/v1/chat/completions';

  const messages = [{ role: 'system', content: systemPrompt }];
  for (const msg of history.slice(-env.AI_MAX_CONTEXT_MESSAGES || -20)) {
    messages.push({ role: msg.role === 'assistant' ? 'assistant' : 'user', content: msg.content || '' });
  }
  messages.push({ role: 'user', content: userMessage });

  const response = await fetch(url, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model,
      messages,
      temperature: (env.AI_TEMPERATURE || 0.4),
      max_tokens:  env.AI_MAX_OUTPUT_TOKENS || 2048,
      stream:      true,
    }),
  });

  if (!response.ok || !response.body) {
    const errText = await response.text().catch(() => 'Sin detalles');
    throw new Error(`OpenAI API Error (${response.status}): ${errText}`);
  }

  const reader  = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer    = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const dataStr = line.slice(6).trim();
        if (dataStr === '[DONE]') break;
        try {
          const jsonChunk = JSON.parse(dataStr);
          const textChunk = jsonChunk.choices?.[0]?.delta?.content;
          if (textChunk) {
            res.write(`data: ${JSON.stringify({ token: textChunk })}\n\n`);
          }
        } catch (e) {}
      }
    }
  }

  res.write('data: [DONE]\n\n');
  res.end();
}

/**
 * Genera una respuesta completa y estructurada (JSON) sin streaming, ideal para planes de rutina o dietas.
 *
 * Soporta SALIDA ESTRUCTURADA NATIVA: si se pasa `responseSchema` (Gemini) o
 * `openaiJsonSchema` (OpenAI), el motor del LLM restringe el JSON al esquema —
 * eliminando alucinaciones de claves y permitiendo prompts mucho más cortos.
 *
 * @param {string} systemPrompt
 * @param {string} userPrompt
 * @param {boolean|object} [options=false] - Retrocompat: booleano = useProModel.
 * @param {boolean} [options.useProModel=false] - Modelo Pro (gemini-2.5-pro / gpt-4o).
 * @param {object}  [options.responseSchema]     - Esquema Gemini (generationConfig.responseSchema).
 * @param {object}  [options.openaiJsonSchema]   - Esquema OpenAI ({ name, strict, schema }).
 * @param {number}  [options.timeoutMs=45000]    - Timeout duro de la llamada al LLM.
 * @returns {Promise<string>} Texto/JSON retornado por el modelo
 */
async function generateStructuredContent(systemPrompt, userPrompt, options = false) {
  // Retrocompatibilidad: llamadas antiguas pasaban un booleano useProModel.
  const opts = (typeof options === 'boolean') ? { useProModel: options } : (options || {});
  const {
    useProModel      = false,
    responseSchema   = null,
    openaiJsonSchema = null,
    timeoutMs        = 45_000,
  } = opts;

  const provider   = env.AI_PROVIDER;
  const controller = new AbortController();
  const timeoutId  = setTimeout(() => controller.abort(), timeoutMs);

  try {
    if (provider === 'gemini') {
      const primaryModel  = useProModel ? (env.GEMINI_MODEL_PRO || 'gemini-3.5-flash') : (env.GEMINI_MODEL || 'gemini-3.5-flash');
      const fallbackModel = env.GEMINI_MODEL || 'gemini-3.5-flash';

      const generationConfig = {
        temperature:      env.AI_TEMPERATURE || 0.3,
        maxOutputTokens:  (env.AI_MAX_OUTPUT_TOKENS || 2048) * 2,
        responseMimeType: 'application/json',
      };
      // Salida estructurada nativa: el modelo no puede desviarse del esquema.
      if (responseSchema) generationConfig.responseSchema = responseSchema;

      const callGemini = async (model) => {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`;
        const response = await fetch(url, {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: systemPrompt }] },
            contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
            generationConfig,
          }),
          signal: controller.signal,
        });
        if (!response.ok) {
          const errText = await response.text().catch(() => '');
          const e = new Error(`Gemini API Error (${response.status}): ${errText}`);
          e.status = response.status;
          throw e;
        }
        const data = await response.json();
        return data.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
      };

      try {
        return await callGemini(primaryModel);
      } catch (err) {
        // Si el modelo PRO no existe / no está disponible para esta API key (404),
        // caemos al modelo base (flash) para no dejar la generación sin respuesta.
        // Antes, un 404 del modelo pro tumbaba toda la rutina/dieta con HTTP 500.
        if (err.status === 404 && primaryModel !== fallbackModel) {
          logger.warn('Modelo Gemini pro no disponible (404); usando fallback', {
            primaryModel, fallbackModel,
          });
          return await callGemini(fallbackModel);
        }
        throw err;
      }
    } else {
      const model = useProModel ? (env.OPENAI_MODEL_PRO || 'gpt-4o') : (env.OPENAI_MODEL || 'gpt-4o-mini');
      const url   = 'https://api.openai.com/v1/chat/completions';

      // Structured Outputs estricto si hay esquema; si no, JSON libre.
      const response_format = openaiJsonSchema
        ? { type: 'json_schema', json_schema: openaiJsonSchema }
        : { type: 'json_object' };

      const response = await fetch(url, {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          temperature: env.AI_TEMPERATURE || 0.3,
          response_format,
        }),
        signal: controller.signal,
      });

      if (!response.ok) {
        const errText = await response.text().catch(() => '');
        throw new Error(`OpenAI API Error (${response.status}): ${errText}`);
      }
      const data = await response.json();
      return data.choices?.[0]?.message?.content || '{}';
    }
  } catch (err) {
    if (err.name === 'AbortError') {
      throw new Error(`Timeout (${timeoutMs}ms) esperando respuesta estructurada del LLM (${provider}).`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }
}

module.exports = {
  generateChatStreamSSE,
  generateStructuredContent,
};
