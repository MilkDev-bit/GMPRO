/**
 * @file packages_shared/security/errorHandler.js
 * @description Manejador centralizado de errores para producción.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP Top 10 Mitigaciones:                                         ║
 * ║  • A09:2021 — Security Logging and Monitoring Failures              ║
 * ║    → Loguea todos los errores con contexto de seguridad             ║
 * ║  • A05:2021 — Security Misconfiguration                             ║
 * ║    → NUNCA expone stack traces, rutas internas o nombres de módulos  ║
 * ║      en producción. Un stack trace revela tecnología, versiones y   ║
 * ║      rutas de archivos que facilitan ataques dirigidos.             ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 */

'use strict';

const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('error-handler');
const isProduction = process.env.NODE_ENV === 'production';

/**
 * Normaliza cualquier error a una estructura estándar de respuesta.
 * Separa lo que se LOG (todo) de lo que se RESPONDE al cliente (mínimo).
 *
 * @param {Error|*} err - El error capturado
 * @returns {{ statusCode: number, clientMessage: string, logData: object }}
 */
function normalizeError(err) {
  // ─── Errores de validación (express-validator, Joi, Zod) ────────────────
  if (err.type === 'validation' || err.name === 'ValidationError') {
    return {
      statusCode: 422,
      clientMessage: err.message || 'Datos de entrada inválidos.',
      logData: { type: 'VALIDATION_ERROR', details: err.details || err.message },
    };
  }

  // ─── Errores de autenticación JWT ────────────────────────────────────────
  if (err.name === 'JsonWebTokenError') {
    return {
      statusCode: 401,
      clientMessage: 'Token de autenticación inválido.',
      logData: { type: 'JWT_INVALID', jwtError: err.message },
    };
  }

  if (err.name === 'TokenExpiredError') {
    return {
      statusCode: 401,
      clientMessage: 'La sesión ha expirado. Por favor, inicia sesión nuevamente.',
      logData: { type: 'JWT_EXPIRED', expiredAt: err.expiredAt },
    };
  }

  if (err.name === 'NotBeforeError') {
    return {
      statusCode: 401,
      clientMessage: 'Token aún no válido.',
      logData: { type: 'JWT_NOT_BEFORE' },
    };
  }

  // ─── Errores de parsing de body (payload malformado) ─────────────────────
  if (err.type === 'entity.parse.failed') {
    return {
      statusCode: 400,
      clientMessage: 'El cuerpo de la solicitud no es un JSON válido.',
      logData: { type: 'JSON_PARSE_ERROR' },
    };
  }

  // ─── Errores de tamaño de payload ────────────────────────────────────────
  if (err.type === 'entity.too.large' || err.status === 413) {
    return {
      statusCode: 413,
      clientMessage: 'El cuerpo de la solicitud es demasiado grande.',
      logData: { type: 'PAYLOAD_TOO_LARGE' },
    };
  }

  // ─── Errores de CORS ──────────────────────────────────────────────────────
  if (err.message?.includes('Not allowed by CORS') || err.message?.includes('Origen no autorizado')) {
    return {
      statusCode: 403,
      clientMessage: 'Acceso denegado por política de seguridad.',
      logData: { type: 'CORS_VIOLATION', origin: err.origin },
    };
  }

  // ─── Errores de Supabase/PostgreSQL ──────────────────────────────────────
  if (err.code && typeof err.code === 'string' && err.code.startsWith('2')) {
    // Códigos 2xxxx son errores de PostgreSQL
    // NUNCA exponer el mensaje de error de Postgres (contiene info de schema)
    return {
      statusCode: 500,
      clientMessage: 'Error al procesar la solicitud en la base de datos.',
      logData: { type: 'DATABASE_ERROR', pgCode: err.code, pgDetail: err.detail },
    };
  }

  // ─── Errores de Stripe ────────────────────────────────────────────────────
  if (err.type?.startsWith('Stripe')) {
    return {
      statusCode: err.statusCode || 402,
      clientMessage: err.raw?.message || 'Error al procesar el pago.',
      logData: { type: 'STRIPE_ERROR', stripeType: err.type, stripeCode: err.code },
    };
  }

  // ─── Error con statusCode explícito (errores propios del negocio) ─────────
  if (err.status || err.statusCode) {
    const code = err.status || err.statusCode;
    return {
      statusCode: code,
      clientMessage: err.message || 'Error al procesar la solicitud.',
      logData: { type: 'APP_ERROR', originalMessage: err.message },
    };
  }

  // ─── Error genérico (500) ─────────────────────────────────────────────────
  return {
    statusCode: 500,
    // En producción: mensaje genérico. En desarrollo: mensaje real para debugging.
    clientMessage: isProduction
      ? 'Ocurrió un error interno. Por favor, intenta más tarde.'
      : (err.message || 'Error interno del servidor.'),
    logData: {
      type: 'INTERNAL_ERROR',
      originalMessage: err.message,
      // Solo el nombre del error en el log (no el stack completo en el campo de datos)
    },
  };
}

/**
 * Middleware de manejo de errores de Express (4 parámetros obligatorios).
 * Debe registrarse AL FINAL de todos los middlewares y rutas.
 *
 * Uso en main.js:
 *   app.use(createErrorHandler('auth-service'));
 *
 * @param {string} serviceName - Nombre del servicio para contexto en logs
 * @returns {import('express').ErrorRequestHandler}
 */
function createErrorHandler(serviceName = 'unknown') {
  // eslint-disable-next-line no-unused-vars
  return (err, req, res, _next) => {
    const { statusCode, clientMessage, logData } = normalizeError(err);

    // Nivel de log según severidad del error
    const logLevel = statusCode >= 500 ? 'error' : statusCode >= 400 ? 'warn' : 'info';

    logger[logLevel](`[${serviceName}] Error en request`, {
      ...logData,
      statusCode,
      method: req.method,
      path: req.path,
      ip: req.ip,
      userId: req.user?.id,                         // Si hay JWT verificado
      requestId: req.headers['x-request-id'],
      userAgent: req.headers['user-agent']?.substring(0, 200),
      // Stack trace SOLO en logs internos, NUNCA en la respuesta al cliente
      // Solo loguear stack en errores 500 (errores de negocio no necesitan stack)
      ...(statusCode >= 500 && { stack: err.stack }),
    });

    // Respuesta al cliente: mínima información, sin detalles de implementación
    return res.status(statusCode).json({
      success: false,
      data: null,
      error: clientMessage,
      // requestId: permite al cliente reportar el error para soporte
      requestId: req.headers['x-request-id'] || null,
    });
  };
}

/**
 * Middleware para rutas no encontradas (404).
 * Registrar como 'not found' en lugar de dejar que Express responda con HTML.
 *
 * @returns {import('express').RequestHandler}
 */
function createNotFoundHandler() {
  return (req, res) => {
    // Log de intentos a rutas inexistentes (puede indicar scanning de vulnerabilidades)
    logger.warn('Ruta no encontrada', {
      event: 'ROUTE_NOT_FOUND',
      method: req.method,
      path: req.path,
      ip: req.ip,
    });

    res.status(404).json({
      success: false,
      data: null,
      error: `La ruta ${req.method} ${req.path} no existe en este servicio.`,
    });
  };
}

module.exports = { createErrorHandler, createNotFoundHandler };
