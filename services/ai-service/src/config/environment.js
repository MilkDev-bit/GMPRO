/**
 * @file services/ai-service/src/config/environment.js
 * @description Validación de variables de entorno para ai-service.
 */
'use strict';

const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('ai-service:config');

/**
 * Valida una API key de Supabase admitiendo los DOS formatos vigentes:
 *
 *   · Legacy  : JWT que empieza por 'eyJ' y supera los 100 caracteres.
 *   · Actual  : 'sb_secret_...' / 'sb_publishable_...', ~40 caracteres.
 *
 * El validador anterior exigía length > 100, lo que rechazaba las claves
 * nuevas y dejaba el servicio en crash loop con un mensaje engañoso
 * ("formato inválido") pese a que la clave era correcta.
 */
function isValidSupabaseKey(v) {
  if (!v) return false;
  if (v.startsWith('sb_secret_') || v.startsWith('sb_publishable_')) return v.length >= 20;
  if (v.startsWith('eyJ')) return v.length > 100;
  return false;
}

const ENV_SCHEMA = [
  { key: 'NODE_ENV',                required: true,  validate: (v) => ['development','production','test'].includes(v) },
  { key: 'PORT',                    required: true,  validate: (v) => +v > 0 },
  { key: 'SUPABASE_URL',            required: true,  validate: (v) => v.startsWith('https://') },
  { key: 'SUPABASE_SERVICE_ROLE_KEY', required: true, validate: isValidSupabaseKey },
  { key: 'SUPABASE_DB_SCHEMA',      required: true },
  { key: 'JWT_SECRET',              required: true,  validate: (v) => v.length >= 64 },
  { key: 'INTER_SERVICE_SECRET',    required: true,  validate: (v) => v.length >= 32 },
  { key: 'AI_PROVIDER',             required: true,  validate: (v) => ['gemini','openai'].includes(v.toLowerCase()) },
  { key: 'FITNESS_SERVICE_INTERNAL_URL', required: true, validate: (v) => v.startsWith('http') },
];

function validateEnvironment() {
  const errors = [];
  for (const { key, required, validate } of ENV_SCHEMA) {
    const value = process.env[key];
    if (!value) {
      if (required) errors.push(`  ✗ ${key}: FALTANTE`);
      continue;
    }
    if (validate && !validate(value)) {
      errors.push(`  ✗ ${key}: valor o formato inválido`);
    }
  }

  const provider = (process.env.AI_PROVIDER || 'gemini').toLowerCase();
  if (provider === 'gemini' && !process.env.GEMINI_API_KEY) {
    errors.push('  ✗ GEMINI_API_KEY: requerido para AI_PROVIDER=gemini');
  }
  if (provider === 'openai' && !process.env.OPENAI_API_KEY) {
    errors.push('  ✗ OPENAI_API_KEY: requerido para AI_PROVIDER=openai');
  }

  if (errors.length > 0) {
    logger.error('Configuración inválida en ai-service:\n' + errors.join('\n'));
    process.exit(1);
  }
  logger.info('Variables de entorno validadas en ai-service', { provider, env: process.env.NODE_ENV });
}

validateEnvironment();

module.exports = {
  NODE_ENV:                   process.env.NODE_ENV,
  PORT:                       parseInt(process.env.PORT, 10),
  IS_PRODUCTION:              process.env.NODE_ENV === 'production',
  SUPABASE_URL:               process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY:  process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA:         process.env.SUPABASE_DB_SCHEMA || 'ai_service_db',
  JWT_SECRET:                 process.env.JWT_SECRET,
  JWT_ALGORITHM:              process.env.JWT_ALGORITHM || 'HS512',
  AI_PROVIDER:                (process.env.AI_PROVIDER || 'gemini').toLowerCase(),
  GEMINI_API_KEY:             process.env.GEMINI_API_KEY,
  GEMINI_MODEL:               process.env.GEMINI_MODEL || 'gemini-2.0-flash',
  GEMINI_MODEL_PRO:           process.env.GEMINI_MODEL_PRO || 'gemini-2.5-pro',
  OPENAI_API_KEY:             process.env.OPENAI_API_KEY,
  OPENAI_MODEL:               process.env.OPENAI_MODEL || 'gpt-4o-mini',
  OPENAI_MODEL_PRO:           process.env.OPENAI_MODEL_PRO || 'gpt-4o',
  AI_MAX_INPUT_TOKENS:        parseInt(process.env.AI_MAX_INPUT_TOKENS || '4096', 10),
  AI_MAX_OUTPUT_TOKENS:       parseInt(process.env.AI_MAX_OUTPUT_TOKENS || '2048', 10),
  AI_TEMPERATURE:             parseFloat(process.env.AI_TEMPERATURE || '0.4'),
  AI_SYSTEM_PERSONA:          process.env.AI_SYSTEM_PERSONA || 'Eres GymBot, asistente personal de fitness y nutrición deportiva de GymPro. Responde en español. Sé motivador, científico y profesional. Nunca proporciones diagnósticos ni prescripciones médicas.',
  FITNESS_SERVICE_INTERNAL_URL: process.env.FITNESS_SERVICE_INTERNAL_URL,
  INTER_SERVICE_SECRET:       process.env.INTER_SERVICE_SECRET,
  INTER_SERVICE_TIMEOUT_MS:   parseInt(process.env.INTER_SERVICE_TIMEOUT_MS || '4000', 10),
  REDIS_URL:                  process.env.REDIS_URL || null,
  AI_RECOMMENDATION_CACHE_TTL: parseInt(process.env.AI_RECOMMENDATION_CACHE_TTL || '86400', 10),
};
