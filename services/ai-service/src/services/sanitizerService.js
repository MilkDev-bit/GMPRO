/**
 * @file services/ai-service/src/services/sanitizerService.js
 * @description Mitigación de ataques de Prompt Injection, Jailbreak y sanitización de entradas al LLM.
 *
 * MITIGACIONES IMPLEMENTADAS:
 *   1. Límite estricto de caracteres y estimación de tokens (previene agotamiento de cuotas / DoS).
 *   2. Detección y neutralización de patrones de Jailbreak ("Ignore previous instructions", "DAN Mode", "Override prompt").
 *   3. Escapado de delimitadores de sistema (`<|im_start|>`, `### System`, etc.) que intentan confundir al modelo.
 */

'use strict';

const env                   = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:sanitizerService');

// Patrones regex comúnmente utilizados en intentos de Prompt Injection / Jailbreak
const INJECTION_PATTERNS = [
  /ignore\s+(all\s+)?(previous|above)\s+instructions/i,
  /olvida\s+(todas\s+)?las\s+instrucciones\s+(anteriores|previas)/i,
  /ignora\s+(todas\s+)?las\s+instrucciones/i,
  /system\s+prompt\s+override/i,
  /you\s+are\s+now\s+in\s+DAN\s+mode/i,
  /act\s+as\s+if\s+you\s+have\s+no\s+restrictions/i,
  /desactiva\s+tus\s+filtros/i,
  /<\|im_start\|>/i,
  /<\|im_end\|>/i,
  /###\s*System/i,
  /\[SYSTEM_DIRECTIVE\]/i,
];

/**
 * Sanitiza y valida la entrada del usuario antes de enviarla al LLM.
 *
 * @param {string} rawInput
 * @returns {{ sanitized: string, isValid: boolean, rejectionReason: string|null }}
 */
function sanitizeUserPrompt(rawInput) {
  if (!rawInput || typeof rawInput !== 'string') {
    return { sanitized: '', isValid: false, rejectionReason: 'El mensaje no puede estar vacío.' };
  }

  const trimmed = rawInput.trim();

  // 1. Límite de caracteres (aprox 4 caracteres por token. Si max input tokens es 4096, máximo 16,000 chars)
  const maxChars = (env.AI_MAX_INPUT_TOKENS || 4096) * 4;
  if (trimmed.length > maxChars) {
    logger.warn('Prompt excede límite de caracteres', { length: trimmed.length, maxChars });
    return {
      sanitized: '',
      isValid: false,
      rejectionReason: `El mensaje es demasiado largo (máximo ${maxChars} caracteres). Por favor sé más conciso.`,
    };
  }

  // 2. Detección de patrones de Prompt Injection / Jailbreak
  for (const pattern of INJECTION_PATTERNS) {
    if (pattern.test(trimmed)) {
      logger.warn('Intento de Prompt Injection / Jailbreak detectado y bloqueado', {
        pattern: pattern.toString(),
        snippet: trimmed.substring(0, 100),
      });
      return {
        sanitized: '',
        isValid: false,
        rejectionReason: 'El mensaje contiene instrucciones de sistema no permitidas por las políticas de seguridad de GymPro.',
      };
    }
  }

  // 3. Sanitizar delimitadores que puedan alterar el formateo del prompt
  let sanitized = trimmed
    .replace(/```system/gi, '```text')
    .replace(/<\|.*?\|>/g, '')
    .replace(/\[SYSTEM.*?\]/gi, '');

  return { sanitized, isValid: true, rejectionReason: null };
}

module.exports = { sanitizeUserPrompt };
