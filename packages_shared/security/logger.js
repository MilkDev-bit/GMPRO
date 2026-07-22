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

// ─── Formato de producción: JSON estructurado ──────────────────────────────────
// Cada línea de log es un objeto JSON parseable por agregadores de logs.
// Campos estándar: timestamp, level, service, message, + metadata de seguridad.
const productionFormat = combine(
  timestamp({ format: 'YYYY-MM-DDTHH:mm:ss.SSSZ' }),
  errors({ stack: true }),  // Captura stack traces en el campo 'stack'
  json()                    // Serializa todo como JSON — nunca como texto libre
);

// ─── Formato de desarrollo: legible en consola ────────────────────────────────
const developmentFormat = combine(
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

module.exports = { createServiceLogger, __resetLoggerCache };
