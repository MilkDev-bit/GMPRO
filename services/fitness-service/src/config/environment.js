/**
 * @file services/fitness-service/src/config/environment.js
 * @description Validación y tipado de variables de entorno para fitness-service.
 */
"use strict";

const {
  createServiceLogger,
} = require("../../../../packages_shared/security/logger");
const logger = createServiceLogger("fitness-service:config");

/**
 * Valida una API key de Supabase detectando truncamiento.
 * Formatos vigentes: 'sb_secret_...'/'sb_publishable_...' (~40+ chars) o el
 * JWT legacy 'eyJ...' (200+). Antes: `v.length > 30`, que aceptaba cualquier
 * cadena de 31 caracteres — no detectaba una key cortada.
 */
function isValidSupabaseKey(v) {
  if (!v) return false;
  if (v.startsWith("sb_secret_") || v.startsWith("sb_publishable_")) return v.length >= 20;
  if (v.startsWith("eyJ")) return v.length > 100;
  return false;
}

const ENV_SCHEMA = [
  {
    key: "NODE_ENV",
    required: true,
    validate: (v) => ["development", "production", "test"].includes(v),
  },
  { key: "PORT", required: true, validate: (v) => +v > 0 },
  {
    key: "SUPABASE_URL",
    required: true,
    validate: (v) => v.startsWith("https://"),
  },
  {
    key: "SUPABASE_SERVICE_ROLE_KEY",
    required: true,
    validate: isValidSupabaseKey,
  },
  { key: "SUPABASE_DB_SCHEMA", required: true },
  // JWT_SECRET (HS512) opcional tras migración a RS256: requerido SOLO si no hay JWT_PUBLIC_KEY.
  { key: "JWT_SECRET", required: false, validate: (v) => !v || v.length >= 64 },
  {
    key: "INTER_SERVICE_SECRET",
    required: true,
    validate: (v) => v.length >= 32,
  },
  { key: "CORS_ALLOWED_ORIGINS", required: true },
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
  // Debe existir AL MENOS un mecanismo de verificación JWT: HS512 (JWT_SECRET) o RS256 (JWT_PUBLIC_KEY).
  if (!process.env.JWT_SECRET && !process.env.JWT_PUBLIC_KEY) {
    errors.push('  ✗ JWT: falta JWT_SECRET (HS512) o JWT_PUBLIC_KEY (RS256) — se requiere al menos uno');
  }

  if (errors.length > 0) {
    logger.error(
      "Configuración inválida en fitness-service:\n" + errors.join("\n"),
    );
    process.exit(1);
  }
  logger.info("Variables de entorno validadas en fitness-service", {
    env: process.env.NODE_ENV,
  });
}

validateEnvironment();

module.exports = {
  NODE_ENV: process.env.NODE_ENV,
  PORT: parseInt(process.env.PORT, 10),
  IS_PRODUCTION: process.env.NODE_ENV === "production",
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_SCHEMA: process.env.SUPABASE_DB_SCHEMA || "fitness_service_db",
  // Mínimo privilegio (CLD-1): si ambos están presentes, el cliente usa el rol
  // svc_fitness (JWT scopeado) en vez de SERVICE_ROLE_KEY. Opcionales → coexistencia.
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY,
  SUPABASE_JWT_SECRET: process.env.SUPABASE_JWT_SECRET,
  JWT_SECRET: process.env.JWT_SECRET,
  JWT_ALGORITHM: process.env.JWT_ALGORITHM || "HS512",
  INTER_SERVICE_SECRET: process.env.INTER_SERVICE_SECRET,
  REDIS_URL: process.env.REDIS_URL || null,
  EXERCISE_CATALOG_CACHE_TTL: parseInt(
    process.env.EXERCISE_CATALOG_CACHE_TTL || "3600",
    10,
  ),
  DEFAULT_PAGE_SIZE: parseInt(process.env.DEFAULT_PAGE_SIZE || "20", 10),
  MAX_PAGE_SIZE: parseInt(process.env.MAX_PAGE_SIZE || "100", 10),
  CORS_ALLOWED_ORIGINS: process.env.CORS_ALLOWED_ORIGINS || "",

  // ── Correos transaccionales (Resend + cola BullMQ) ────────────────────────
  // Sin RESEND_API_KEY el proveedor entra en modo simulación (loguea).
  // Sin REDIS_URL la cola degrada a envío directo best-effort.
  RESEND_API_KEY: process.env.RESEND_API_KEY || null,
  EMAIL_FROM: process.env.EMAIL_FROM || "noreply@gympro.app",
  EMAIL_FROM_NAME: process.env.EMAIL_FROM_NAME || "GymPro",
  EMAIL_WORKER_CONCURRENCY: process.env.EMAIL_WORKER_CONCURRENCY || "5",
  APP_DEEPLINK_URL: process.env.APP_DEEPLINK_URL || "https://app.gympro.com",
};
