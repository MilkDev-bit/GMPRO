/**
 * @file services/access-service/src/config/environment.js
 * @description Validación de variables de entorno para access-service.
 */
'use strict';

const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('access-service:config');

// Soportar tanto AES_ENCRYPTION_KEY como QR_SECRET_KEY (retrocompatibilidad)
const getAesKey = () => process.env.AES_ENCRYPTION_KEY || process.env.QR_SECRET_KEY;

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
  // JWT_SECRET (HS512) opcional tras migración a RS256: requerido SOLO si no hay JWT_PUBLIC_KEY.
  { key: 'JWT_SECRET',              required: false, validate: (v) => !v || v.length >= 64 },
  { key: 'JWT_ALGORITHM',           required: true },
  { key: 'TURNSTILE_API_KEY',       required: true,  validate: (v) => v.length >= 32 },
  { key: 'PAYMENT_SERVICE_INTERNAL_URL', required: true, validate: (v) => v.startsWith('http') },
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

  const aesKey = getAesKey();
  if (!aesKey) {
    errors.push('  ✗ AES_ENCRYPTION_KEY / QR_SECRET_KEY: FALTANTE');
  } else if (!/^[0-9a-fA-F]{64}$/.test(aesKey)) {
    errors.push('  ✗ AES_ENCRYPTION_KEY / QR_SECRET_KEY: debe ser una cadena hexadecimal exacta de 64 caracteres (32 bytes para AES-256)');
  }

  // Debe existir AL MENOS un mecanismo de verificación JWT: HS512 (JWT_SECRET) o RS256 (JWT_PUBLIC_KEY).
  if (!process.env.JWT_SECRET && !process.env.JWT_PUBLIC_KEY) {
    errors.push('  ✗ JWT: falta JWT_SECRET (HS512) o JWT_PUBLIC_KEY (RS256) — se requiere al menos uno');
  }

  if (errors.length > 0) {
    logger.error('Configuración inválida en access-service:\n' + errors.join('\n'));
    process.exit(1);
  }
  logger.info('Variables de entorno validadas en access-service', { env: process.env.NODE_ENV });
}

validateEnvironment();

module.exports = {
  NODE_ENV:                   process.env.NODE_ENV,
  PORT:                       parseInt(process.env.PORT, 10),
  IS_PRODUCTION:              process.env.NODE_ENV === 'production',
  SUPABASE_URL:               process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY:  process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA:         process.env.SUPABASE_DB_SCHEMA || 'access_service_db',
  // Mínimo privilegio (CLD-1): cadena pg del rol svc_access (pooler de Supabase).
  ACCESS_DATABASE_URL:        process.env.ACCESS_DATABASE_URL,
  JWT_SECRET:                 process.env.JWT_SECRET,
  JWT_ALGORITHM:              process.env.JWT_ALGORITHM || 'HS512',
  AES_ENCRYPTION_KEY:         getAesKey(),
  TURNSTILE_API_KEY:          process.env.TURNSTILE_API_KEY,
  PAYMENT_SERVICE_INTERNAL_URL: process.env.PAYMENT_SERVICE_INTERNAL_URL,
  INTER_SERVICE_SECRET:       process.env.INTER_SERVICE_SECRET,
  INTER_SERVICE_TIMEOUT_MS:   parseInt(process.env.INTER_SERVICE_TIMEOUT_MS || '2000', 10),
  REDIS_URL:                  process.env.REDIS_URL || null,
  CORS_ALLOWED_ORIGINS:       process.env.CORS_ALLOWED_ORIGINS || '',
  QR_TTL_SECONDS:             parseInt(process.env.QR_TTL_SECONDS || '30', 10),

  // ── RBAC: roles internos autorizados para operaciones de mostrador ──────────
  // Antes 'staff'/'admin' estaban hardcodeados en main.js, ticketRoutes.js y el
  // controlador. Se externaliza: STAFF_ROLES = lista separada por comas, con
  // fallback seguro. Añadir un rol (p.ej. 'gerente') ya no requiere tocar código.
  // Se normaliza a minúsculas/trim para tolerar variaciones de configuración.
  STAFF_ROLES: (process.env.STAFF_ROLES || 'staff,admin')
    .split(',')
    .map((r) => r.trim().toLowerCase())
    .filter(Boolean),

  // Límites de emisión (env-overridable) para rutas sensibles de acceso.
  RATE_LIMIT_TICKET_MAX:      parseInt(process.env.RATE_LIMIT_TICKET_MAX || '30', 10),
  RATE_LIMIT_QR_MAX:          parseInt(process.env.RATE_LIMIT_QR_MAX || '10', 10),
  // ── Autenticación de terminales ZKTeco ADMS (/iclock/*) ────────────────────
  // ZK_ALLOWED_SERIALS: lista separada por comas de números de serie autorizados.
  // ZK_PUSH_KEY: clave compartida que la terminal envía (header x-adms-key o ?key=).
  // Ambas DEBEN configurarse en producción para cerrar los endpoints de biometría.
  ZK_ALLOWED_SERIALS:         process.env.ZK_ALLOWED_SERIALS || '',
  ZK_PUSH_KEY:                process.env.ZK_PUSH_KEY || null,
};
