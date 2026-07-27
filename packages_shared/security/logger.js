/**
 * @file packages_shared/security/logger.js
 * @description Logger de seguridad centralizado (Winston).
 *
 * Produce logs estructurados en formato JSON, ideales para ser ingestados por
 * Railway Logs, Datadog, Logtail o cualquier agregador SIEM.
 *
 * OWASP A09:2021 — Security Logging and Monitoring Failures:
 *   Sin logs estructurados de seguridad, los incidentes son indetectables.
 *   Este logger registra eventos de seguridad con campos estandarizados para
 *   facilitar la correlación y el alerting automatizado.
 */

'use strict';

const { createLogger, format, transports } = require('winston');
const { combine, timestamp, json, errors, printf, colorize } = format;

// ═══════════════════════════════════════════════════════════════════════════
// REDACCIÓN DE DATOS SENSIBLES (OWASP A09 / CWE-532)
// Los logs se ingieren en agregadores (Railway/Datadog/CloudWatch); si un campo
// sensible llega sin enmascarar, cualquiera con acceso a logs compromete el
// sistema. Este filtro intercepta TODO log (dev y prod) antes de serializar y
// redacta: (a) valores de claves sensibles conocidas, y (b) valores que
// coincidan con patrones de secreto (JWT, claves Stripe/Supabase, Bearer),
// aunque la clave no sea "sensible". Es una red de seguridad, no un sustituto
// de no loguear datos sensibles a propósito.
// ═══════════════════════════════════════════════════════════════════════════
const REDACTED = '[REDACTED]';
const MAX_REDACT_DEPTH = 8;

// Claves cuyo VALOR se redacta por completo (substring, case-insensitive).
const SENSITIVE_KEY = /pass(word|wd)?|pwd|secret|token|authorization|api[_-]?key|apikey|cookie|credit[_-]?card|card[_-]?number|cvv|cvc|\bssn\b|private[_-]?key|refresh_token|access_token|id_token|client_secret|webhook_secret|inter_service_secret|service_role|pin_terminal|bearer/i;

// Patrones de secreto de alta señal: se enmascaran dentro de CUALQUIER string
// (mensaje, stack, valores) aunque la clave no sea sensible.
const SECRET_VALUE_PATTERNS = [
  /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, // JWT (header.payload.sig)
  /\b[rs]k_(live|test)_[A-Za-z0-9]{8,}/g,                        // Stripe secret/restricted keys
  /\bwhsec_[A-Za-z0-9]{8,}/g,                                    // Stripe webhook secret
  /\bsb_secret_[A-Za-z0-9]{8,}/g,                                // Supabase secret key
  /Bearer\s+[A-Za-z0-9._-]{8,}/gi,                               // Bearer <token>
];

function redactString(str) {
  let out = str;
  for (const re of SECRET_VALUE_PATTERNS) out = out.replace(re, REDACTED);
  return out;
}

function redactValue(val, depth, seen) {
  if (depth > MAX_REDACT_DEPTH) return '[TRUNCATED]';
  if (typeof val === 'string') return redactString(val);
  if (Array.isArray(val)) return val.map((v) => redactValue(v, depth + 1, seen));
  if (val && typeof val === 'object') {
    if (seen.has(val)) return '[CIRCULAR]';
    seen.add(val);
    const out = {};
    for (const [k, v] of Object.entries(val)) {
      out[k] = SENSITIVE_KEY.test(k) ? REDACTED : redactValue(v, depth + 1, seen);
    }
    return out;
  }
  return val; // números, booleanos, null, undefined
}

/**
 * Redacta in-place las propiedades string-keyed del envelope de winston. Los
 * valores redactados son CLONES (no muta los objetos originales del caller, p.
 * ej. req.body). Preserva los Symbols internos de winston (level/message).
 * @param {object} info
 * @returns {object}
 */
function redactLogInfo(info) {
  const seen = new WeakSet();
  for (const key of Object.keys(info)) {
    if (key === 'level' || key === 'timestamp') continue; // estructurales, no sensibles
    info[key] = SENSITIVE_KEY.test(key) ? REDACTED : redactValue(info[key], 1, seen);
  }
  return info;
}

// Format de winston que aplica la redacción a cada registro.
const redactFormat = format((info) => redactLogInfo(info));

// ─── Formato de producción: JSON estructurado ──────────────────────────────────
// Cada línea de log es un objeto JSON parseable por agregadores de logs.
// Campos estándar: timestamp, level, service, message, + metadata de seguridad.
const productionFormat = combine(
  timestamp({ format: 'YYYY-MM-DDTHH:mm:ss.SSSZ' }),
  errors({ stack: true }),  // Captura stack traces en el campo 'stack'
  redactFormat(),           // ← redacta datos sensibles ANTES de serializar
  json()                    // Serializa todo como JSON — nunca como texto libre
);

// ─── Formato de desarrollo: legible en consola ────────────────────────────────
const developmentFormat = combine(
  errors({ stack: true }),
  redactFormat(),           // ← también en dev: los logs locales pueden filtrarse
  colorize(),
  timestamp({ format: 'HH:mm:ss' }),
  printf(({ level, message, timestamp: ts, service, ...meta }) => {
    const metaStr = Object.keys(meta).length ? `\n  ${JSON.stringify(meta, null, 2)}` : '';
    return `[${ts}] [${service || 'app'}] ${level}: ${message}${metaStr}`;
  })
);

const isProduction = process.env.NODE_ENV === 'production';

/**
 * Caché de loggers por servicio.
 *
 * PROBLEMA QUE RESUELVE:
 * `createServiceLogger` se llama desde muchos módulos (emailQueue,
 * emailProvider, config, rateLimiter…). Cada llamada creaba un logger
 * Winston NUEVO y, al llevar `exceptionHandlers`/`rejectionHandlers`,
 * cada uno registraba SUS PROPIOS listeners en `process`. De ahí el
 * aviso:
 *
 *   MaxListenersExceededWarning: 11 uncaughtException listeners added
 *
 * No era una fuga de memoria real, pero sí un problema serio: ante una
 * excepción no capturada se disparaban 11 rutinas de manejo en paralelo,
 * con 11 escrituras a consola y 11 posibles cierres a medias.
 *
 * Ahora se reutiliza la instancia por nombre de servicio, así que los
 * handlers de proceso se registran UNA sola vez por servicio.
 */
const loggerCache = new Map();

/**
 * Crea (o reutiliza) el logger asociado a un servicio.
 *
 * Las llamadas con el mismo `serviceName` devuelven SIEMPRE la misma
 * instancia. Para etiquetar submódulos usa un sufijo distinto
 * ('fitness-service:emailQueue'): tendrá su propia instancia, pero solo
 * la primera de cada nombre registra handlers.
 *
 * @param {string} serviceName - Nombre del microservicio (ej: 'auth-service')
 * @returns {import('winston').Logger}
 */
function createServiceLogger(serviceName) {
  const cached = loggerCache.get(serviceName);
  if (cached) return cached;

  // Solo el PRIMER logger creado en el proceso instala los handlers de
  // excepción; los demás se limitan a loguear. Así el comportamiento
  // ante un fallo es único y predecible, sin importar cuántos submódulos
  // pidan un logger.
  const isFirst = loggerCache.size === 0;

  const logger = createLogger({
    level: process.env.LOG_LEVEL || 'info',
    defaultMeta: {
      service: serviceName,
      environment: process.env.NODE_ENV || 'development',
    },
    format: isProduction ? productionFormat : developmentFormat,
    transports: [
      new transports.Console({
        // En producción, solo errores van a stderr; el resto a stdout
        stderrLevels: ['error'],
      }),
      // A09-3/CLD-7: reenvío de eventos de seguridad a Sentry. Devuelve null si
      // no hay SENTRY_DSN → no se añade nada (no-op, sin dependencia en runtime).
      ...([require('./sentry').createSentryTransport(serviceName)].filter(Boolean)),
    ],
    ...(isFirst
      ? {
          // Captura excepciones no manejadas y las loguea antes de salir
          exceptionHandlers: [new transports.Console()],
          rejectionHandlers: [new transports.Console()],
        }
      : {}),
    // No salir del proceso ante excepciones no manejadas (dumb-init lo maneja)
    exitOnError: false,
  });

  loggerCache.set(serviceName, logger);
  return logger;
}

/** Solo para tests: vacía la caché entre casos. */
function __resetLoggerCache() {
  loggerCache.clear();
}

module.exports = {
  createServiceLogger,
  __resetLoggerCache,
  // Exportados para tests / uso puntual de redacción fuera del logger.
  redactLogInfo,
  redactValue,
};
