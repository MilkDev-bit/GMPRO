/**
 * @file services/payment-service/src/config/environment.js
 * @description Validación de variables de entorno para payment-service.
 */
'use strict';

const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('payment-service:config');

const ENV_SCHEMA = [
  { key: 'NODE_ENV',                required: true,  validate: (v) => ['development','production','test'].includes(v) },
  { key: 'PORT',                    required: true,  validate: (v) => +v > 0 },
  { key: 'SUPABASE_URL',            required: true,  validate: (v) => v.startsWith('https://') },
  { key: 'SUPABASE_SERVICE_ROLE_KEY', required: true, validate: (v) => v.length > 100 },
  { key: 'SUPABASE_DB_SCHEMA',      required: true },
  { key: 'JWT_SECRET',              required: true,  validate: (v) => v.length >= 64 },
  { key: 'JWT_ALGORITHM',           required: true },
  { key: 'STRIPE_SECRET_KEY',       required: true,  validate: (v) => v.startsWith('sk_') },
  { key: 'STRIPE_WEBHOOK_SECRET',   required: true,  validate: (v) => v.startsWith('whsec_') },
  // API Key para pagos en efectivo (recepcionista)
  { key: 'CASH_PAYMENT_API_KEY',    required: true,  validate: (v) => v.length >= 32 },
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
      errors.push(`  ✗ ${key}: valor inválido`);
    }
  }
  if (errors.length > 0) {
    logger.error('Configuración inválida:\n' + errors.join('\n'));
    process.exit(1);
  }
  // Advertir si se usa clave de TEST en producción
  if (process.env.NODE_ENV === 'production' && process.env.STRIPE_SECRET_KEY?.startsWith('sk_test_')) {
    logger.error('¡PELIGRO! Usando STRIPE_SECRET_KEY de TEST en producción. Proceso terminado.');
    process.exit(1);
  }
  logger.info('Variables de entorno validadas', { env: process.env.NODE_ENV });
}

validateEnvironment();

module.exports = {
  NODE_ENV:                   process.env.NODE_ENV,
  PORT:                       parseInt(process.env.PORT, 10),
  IS_PRODUCTION:              process.env.NODE_ENV === 'production',
  SUPABASE_URL:               process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY:  process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA:         process.env.SUPABASE_DB_SCHEMA,
  JWT_SECRET:                 process.env.JWT_SECRET,
  JWT_ALGORITHM:              process.env.JWT_ALGORITHM || 'HS512',
  STRIPE_SECRET_KEY:          process.env.STRIPE_SECRET_KEY,
  STRIPE_WEBHOOK_SECRET:      process.env.STRIPE_WEBHOOK_SECRET,
  STRIPE_DEFAULT_CURRENCY:    process.env.STRIPE_DEFAULT_CURRENCY || 'mxn',
  CASH_PAYMENT_API_KEY:       process.env.CASH_PAYMENT_API_KEY,
  INTER_SERVICE_SECRET:       process.env.INTER_SERVICE_SECRET,
  // URL interna del access-service para sincronización inmediata (Railway private networking).
  // Ej.: http://access-service.railway.internal:3002/api/v1/access/internal
  ACCESS_SERVICE_INTERNAL_URL: process.env.ACCESS_SERVICE_INTERNAL_URL || null,
  INTER_SERVICE_TIMEOUT_MS:   parseInt(process.env.INTER_SERVICE_TIMEOUT_MS || '2500', 10),
  REDIS_URL:                  process.env.REDIS_URL || null,
  CORS_ALLOWED_ORIGINS:       process.env.CORS_ALLOWED_ORIGINS || '',
  BUSINESS_NAME:              process.env.BUSINESS_NAME || 'GymPro',
  BUSINESS_RFC:               process.env.BUSINESS_RFC || '',
};
