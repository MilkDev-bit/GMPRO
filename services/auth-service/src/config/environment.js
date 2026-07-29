/**
 * @file services/auth-service/src/config/environment.js
 * @description Validación y carga de variables de entorno al arrancar el proceso.
 *
 * Patrón fail-fast: si falta cualquier variable crítica o tiene un valor
 * inválido, el proceso termina ANTES de inicializar Express o conectarse a Supabase.
 * Así Railway detecta el contenedor como "unhealthy" inmediatamente y alerta.
 */

"use strict";

const {
  createServiceLogger,
} = require("../../../../packages_shared/security/logger");
const logger = createServiceLogger("auth-service:config");

/**
 * Valida una API key de Supabase detectando truncamiento (mismo criterio que
 * access/ai/payment). 'sb_secret_'/'sb_publishable_' ≥20, o JWT legacy 'eyJ' >100.
 */
function isValidSupabaseKey(v) {
  if (!v) return false;
  if (v.startsWith("sb_secret_") || v.startsWith("sb_publishable_")) return v.length >= 20;
  if (v.startsWith("eyJ")) return v.length > 100;
  return false;
}

// ── Definición del schema de variables ────────────────────────────────────────
// Cada entrada describe una variable: obligatoria, tipo y validación opcional.
const ENV_SCHEMA = [
  // Servidor
  {
    key: "NODE_ENV",
    required: true,
    validate: (v) => ["development", "production", "test"].includes(v),
  },
  {
    key: "PORT",
    required: true,
    validate: (v) => Number.isInteger(+v) && +v > 0,
  },

  // Supabase
  {
    key: "SUPABASE_URL",
    required: true,
    validate: (v) => v.startsWith("https://"),
  },
  {
    key: "SUPABASE_SERVICE_ROLE_KEY",
    required: true,
    // Antes: startsWith('sb_secret_') || length>100 — aceptaba una key
    // truncada tipo 'sb_secret_ab'. Ahora exige longitud mínima por formato
    // para detectar truncamiento (mismo criterio en los 5 servicios).
    validate: isValidSupabaseKey,
  },
  { key: "SUPABASE_DB_SCHEMA", required: true },

  // JWT
  { key: "JWT_SECRET", required: true, validate: (v) => v.length >= 64 },
  { key: "JWT_EXPIRES_IN", required: true },
  { key: "JWT_REFRESH_EXPIRES_IN", required: true },
  {
    key: "JWT_ALGORITHM",
    required: true,
    validate: (v) => ["HS256", "HS384", "HS512"].includes(v),
  },

  // Bcrypt
  {
    key: "BCRYPT_ROUNDS",
    required: true,
    validate: (v) => +v >= 10 && +v <= 15,
  },

  // Email
  { key: "RESEND_API_KEY", required: false }, // Opcional en desarrollo
  { key: "EMAIL_FROM", required: false },

  // CORS
  { key: "CORS_ALLOWED_ORIGINS", required: true },
];

function validateEnvironment() {
  const errors = [];

  for (const { key, required, validate } of ENV_SCHEMA) {
    const value = process.env[key];

    if (!value) {
      if (required) errors.push(`  ✗ ${key}: FALTANTE (obligatoria)`);
      continue;
    }

    if (validate && !validate(value)) {
      errors.push(
        `  ✗ ${key}: valor inválido → "${value.substring(0, 30)}..."`,
      );
    }
  }

  if (errors.length > 0) {
    logger.error(
      "Configuración de entorno inválida. Proceso terminado.\n" +
        errors.join("\n"),
    );
    process.exit(1);
  }

  logger.info("Variables de entorno validadas correctamente", {
    nodeEnv: process.env.NODE_ENV,
    jwtAlgorithm: process.env.JWT_ALGORITHM,
    bcryptRounds: process.env.BCRYPT_ROUNDS,
    schema: process.env.SUPABASE_DB_SCHEMA,
  });
}

// Ejecutar validación al importar el módulo (antes de cualquier otra inicialización)
validateEnvironment();

// Exportar valores parseados y normalizados (evitar parseInt() repetidos por el código)
module.exports = {
  NODE_ENV: process.env.NODE_ENV,
  PORT: parseInt(process.env.PORT, 10),
  IS_PRODUCTION: process.env.NODE_ENV === "production",

  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA: process.env.SUPABASE_DB_SCHEMA,

  JWT_SECRET: process.env.JWT_SECRET,
  // A04-1: firma asimétrica (opcional en convivencia). Clave PRIVADA solo en
  // auth-service; admite PEM directo o base64. Si falta, se firma simétrico (HS*).
  JWT_PRIVATE_KEY: process.env.JWT_PRIVATE_KEY
    ? (process.env.JWT_PRIVATE_KEY.includes('BEGIN')
        ? process.env.JWT_PRIVATE_KEY
        : Buffer.from(process.env.JWT_PRIVATE_KEY, 'base64').toString('utf8'))
    : null,
  JWT_SIGN_ALGORITHM: process.env.JWT_SIGN_ALGORITHM || 'RS256',
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
  JWT_REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN,
  JWT_ALGORITHM: process.env.JWT_ALGORITHM,

  BCRYPT_ROUNDS: parseInt(process.env.BCRYPT_ROUNDS, 10),

  RESEND_API_KEY: process.env.RESEND_API_KEY || null,
  EMAIL_FROM: process.env.EMAIL_FROM || "noreply@gympro.app",
  EMAIL_FROM_NAME: process.env.EMAIL_FROM_NAME || "GymPro",

  RATE_LIMIT_LOGIN_MAX: parseInt(process.env.RATE_LIMIT_LOGIN_MAX || "5", 10),
  RATE_LIMIT_LOGIN_WINDOW_MS:
    parseInt(process.env.RATE_LIMIT_LOGIN_WINDOW_MINUTES || "15", 10) * 60_000,

  INTER_SERVICE_SECRET: process.env.INTER_SERVICE_SECRET || null,
  REDIS_URL: process.env.REDIS_URL || null,
  CORS_ALLOWED_ORIGINS: process.env.CORS_ALLOWED_ORIGINS || "",
};
