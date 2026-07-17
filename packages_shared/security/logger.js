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
 * Crea una instancia del logger asociada a un servicio específico.
 *
 * @param {string} serviceName - Nombre del microservicio (ej: 'auth-service')
 * @returns {winston.Logger}
 */
function createServiceLogger(serviceName) {
  return createLogger({
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
    // Captura excepciones no manejadas y las loguea antes de salir
    exceptionHandlers: [new transports.Console()],
    rejectionHandlers: [new transports.Console()],
    // No salir del proceso ante excepciones no manejadas (dumb-init lo maneja)
    exitOnError: false,
  });
}

module.exports = { createServiceLogger };
