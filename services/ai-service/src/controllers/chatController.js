/**
 * @file services/ai-service/src/controllers/chatController.js
 * @description Controlador de chat conversacional SSE con inyección de contexto y sanitización.
 */

'use strict';

const sanitizerService        = require('../services/sanitizerService');
const fitnessContextClient     = require('../services/fitnessContextClient');
const llmClientService         = require('../services/llmClientService');
const historyWindowService     = require('../services/historyWindowService');
const env                      = require('../config/environment');
const { createServiceLogger }  = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:chatController');

/**
 * POST /api/v1/chat/stream
 * Transmite respuesta conversacional de GymBot en SSE Token por Token.
 */
async function streamChat(req, res, next) {
  try {
    const usuarioId   = req.user.id;
    const { message, history = [] } = req.body;

    // 1. Sanitizar el prompt contra intentos de Prompt Injection
    const check = sanitizerService.sanitizeUserPrompt(message);
    if (!check.isValid) {
      return res.status(400).json({
        success: false, data: null, error: check.rejectionReason,
      });
    }

    // 2. Extraer contexto de fitness en paralelo al preprocesamiento
    const userContext = await fitnessContextClient.getUserFitnessContext(usuarioId);

    // 3. Construir system prompt dinámico incorporando la persona base y datos físicos
    let systemPrompt = `${env.AI_SYSTEM_PERSONA}\n\n[DATOS DEL SOCIO - CONTEXTO EN TIEMPO REAL]`;
    if (userContext.ultimas_mediciones && userContext.ultimas_mediciones.length > 0) {
      const last = userContext.ultimas_mediciones[0];
      systemPrompt += `\n• Peso actual: ${last.peso_kg} kg | % Grasa: ${last.porcentaje_grasa || 'N/A'}%`;
    }
    if (userContext.rutinas_activas && userContext.rutinas_activas.length > 0) {
      const rutinasNombres = userContext.rutinas_activas.map((r) => `${r.nombre} (${r.nivel})`).join(', ');
      systemPrompt += `\n• Rutinas activas: ${rutinasNombres}`;
    }
    systemPrompt += '\nUtiliza esta información para personalizar tus consejos y motivación sin reiterarla repetitivamente en cada respuesta.';

    // 4. Ventana móvil sobre el historial.
    //    El historial llega DEL CLIENTE, así que este recorte es un
    //    límite de coste que el backend impone: sin él, un cliente con
    //    un bug puede enviar cientos de turnos y los facturamos enteros.
    const { turns, stats } = historyWindowService.applyWindow(history);

    logger.info('Iniciando sesión de chat SSE', {
      usuarioId,
      provider: env.AI_PROVIDER,
      historyRecibido: stats.received,
      historyEnviado: stats.kept,
      tokensAhorrados: stats.estTokensSaved,
    });

    // 5. Iniciar streaming SSE hacia el cliente Express
    await llmClientService.generateChatStreamSSE(res, systemPrompt, check.sanitized, turns);
  } catch (err) {
    next(err);
  }
}

module.exports = { streamChat };
