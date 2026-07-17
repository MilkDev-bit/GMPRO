/**
 * @file services/fitness-service/src/config/environment.js
 * @description Validación y tipado de variables de entorno para fitness-service.
 */
'use strict';

const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('fitness-service:config');

const ENV_SCHEMA = [
  { key: 'NODE_ENV',                required: true,  validate: (v) => ['development','production','test'].includes(v) },
  { key: 'PORT',                    required: true,  validate: (v) => +v > 0 },
  { key: 'SUPABASE_URL',            required: true,  validate: (v) => v.startsWith('https://') },
  { key: 'SUPABASE_SERVICE_ROLE_KEY', required: true, validate: (v) => v.length > 100 },
  { key: 'SUPABASE_DB_SCHEMA',      required: true },
  { key: 'JWT_SECRET',              required: true,  validate: (v) => v.length >= 64 },
  { key: 'INTER_SERVICE_SECRET',    required: true,  validate: (v) => v.length >= 32 },
  { key: 'CORS_ALLOWED_ORIGINS',    required: true },
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
  if (errors.length > 0) {
    logger.error('Configuración inválida en fitness-service:\n' + errors.join('\n'));
    process.exit(1);
  }
  logger.info('Variables de entorno validadas en fitness-service', { env: process.env.NODE_ENV });
}

validateEnvironment();

module.exports = {
  NODE_ENV:                   process.env.NODE_ENV,
  PORT:                       parseInt(process.env.PORT, 10),
  IS_PRODUCTION:              process.env.NODE_ENV === 'production',
  SUPABASE_URL:               process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY:  process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA:         process.env.SUPABASE_DB_SCHEMA || 'fitness_service_db',
  JWT_SECRET:                 process.env.JWT_SECRET,
  JWT_ALGORITHM:              process.env.JWT_ALGORITHM || 'HS512',
  INTER_SERVICE_SECRET:       process.env.INTER_SERVICE_SECRET,
  REDIS_URL:                  process.env.REDIS_URL || null,
  EXERCISE_CATALOG_CACHE_TTL: parseInt(process.env.EXERCISE_CATALOG_CACHE_TTL || '3600', 10),
  DEFAULT_PAGE_SIZE:          parseInt(process.env.DEFAULT_PAGE_SIZE || '20', 10),
  MAX_PAGE_SIZE:              parseInt(process.env.MAX_PAGE_SIZE || '100', 10),
  CORS_ALLOWED_ORIGINS:       process.env.CORS_ALLOWED_ORIGINS || '',
};
