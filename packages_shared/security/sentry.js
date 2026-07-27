/**
 * @file packages_shared/security/sentry.js
 * @description A09-3 / CLD-7 — Exportación de eventos de seguridad a Sentry.
 *
 * CREDENTIAL-AGNOSTIC: si `SENTRY_DSN` NO está en el entorno, todo es no-op (no
 * rompe el arranque ni requiere la dependencia en runtime). El DSN se inyecta
 * como secreto/variable de entorno, NUNCA se hardcodea.
 *
 * Integración: un transport de winston reenvía a Sentry SOLO los logs cuyo
 * `meta.event` pertenece a SECURITY_ALERT_EVENTS. Como el redactado de secretos
 * ocurre en el pipeline de formato ANTES de los transports, a Sentry llegan datos
 * YA redactados (sin secretos/PII sensible).
 */

'use strict';

const TransportStream = require('winston-transport');

// Eventos que disparan alerta (los que el informe de auditoría marcó como relevantes).
const SECURITY_ALERT_EVENTS = new Set([
  'WEBHOOK_SIGNATURE_INVALID',   // firma de webhook Stripe inválida (posible fraude)
  'INTER_SERVICE_AUTH_FAILED',   // fallo de autenticación M2M
  'LOGIN_FAILED',                // 401 en /login (para detectar ráfagas de fuerza bruta)
  'RATE_LIMITER_STORE_UNAVAILABLE', // Redis del rate limiter caído (fail-closed activo)
  'JWT_BLACKLISTED',             // uso de token revocado
  'INSUFFICIENT_ROLE',           // intento de acceso a recurso sin rol (BFLA)
]);

let Sentry = null;
let initialized = false;

/** Inicializa Sentry UNA vez por proceso. No-op si falta SENTRY_DSN. */
function initSentry(serviceName) {
  if (initialized) return Sentry;
  initialized = true;

  const dsn = process.env.SENTRY_DSN;
  if (!dsn) return null; // sin DSN → desactivado (no rompe nada)

  try {
    // require perezoso: solo se carga si hay DSN y el paquete está instalado.
    // eslint-disable-next-line global-require
    Sentry = require('@sentry/node');
    Sentry.init({
      dsn,
      environment: process.env.NODE_ENV || 'development',
      release: process.env.SENTRY_RELEASE || undefined,
      serverName: serviceName,
      tracesSampleRate: 0,   // solo errores/mensajes de seguridad, no performance
      sendDefaultPii: false, // no enviar PII por defecto
    });
    return Sentry;
  } catch (_e) {
    Sentry = null; // @sentry/node no instalado → degradar a no-op sin crashear
    return null;
  }
}

/** Envía un evento de seguridad a Sentry (no-op si no está inicializado). */
function captureSecurityEvent(event, meta = {}, level = 'warning') {
  if (!Sentry) return;
  try {
    Sentry.withScope((scope) => {
      scope.setLevel(level);
      scope.setTag('event', event);
      if (meta.service) scope.setTag('service', meta.service);
      scope.setContext('security', meta);
      Sentry.captureMessage(`[SECURITY] ${event}`, level);
    });
  } catch (_e) { /* nunca romper el flujo por telemetría */ }
}

/**
 * Transport de winston que reenvía a Sentry los eventos de seguridad.
 * @param {string} serviceName
 * @returns {TransportStream|null} null si no hay SENTRY_DSN (no se añade nada).
 */
function createSentryTransport(serviceName) {
  if (!process.env.SENTRY_DSN) return null;
  initSentry(serviceName);
  if (!Sentry) return null;

  class SentryTransport extends TransportStream {
    log(info, callback) {
      setImmediate(() => this.emit('logged', info));
      const event = info.event;
      if (event && SECURITY_ALERT_EVENTS.has(event)) {
        const level = info.level === 'error' ? 'error' : 'warning';
        // info ya viene redactado por el pipeline de formato del logger.
        const { level: _l, message, timestamp, service, ...rest } = info;
        captureSecurityEvent(event, { service, message, ...rest }, level);
      }
      callback();
    }
  }
  return new SentryTransport({ level: 'warn' });
}

module.exports = {
  initSentry,
  captureSecurityEvent,
  createSentryTransport,
  SECURITY_ALERT_EVENTS,
};
