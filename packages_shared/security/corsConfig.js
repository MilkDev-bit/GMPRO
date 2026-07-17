/**
 * @file packages_shared/security/corsConfig.js
 * @description Política CORS estricta para microservicios GymPro.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP Top 10 Mitigaciones:                                         ║
 * ║  • A01:2021 — Broken Access Control                                 ║
 * ║    → CORS mal configurado permite a sitios maliciosos hacer          ║
 * ║      requests autenticados en nombre del usuario (CSRF via fetch)    ║
 * ║  • A05:2021 — Security Misconfiguration                             ║
 * ║    → origin: '*' expone la API a cualquier dominio                  ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * Fuentes permitidas:
 *   1. App móvil Flutter: No usa CORS (HTTP nativo), pero si se agrega
 *      una webview o panel admin web, sí aplica.
 *   2. Panel de administración web: dominio de la app admin.
 *   3. Scripts locales (Raspberry Pi): No usan navegador → CORS no aplica.
 *   4. Stripe webhooks: No usan navegador → CORS no aplica.
 *
 * IMPORTANTE: Las apps móviles nativas (Flutter) NO están sujetas a CORS.
 * CORS es una política de NAVEGADORES WEB. Las apps móviles pueden hacer
 * requests directamente sin CORS. Solo aplica si tienes una WebView o PWA.
 */

'use strict';

const cors = require('cors');
const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('cors');

/**
 * Parsea y valida la lista de orígenes permitidos desde variable de entorno.
 * Formato esperado: "https://app.tugimnasio.com,https://admin.tugimnasio.com"
 *
 * @returns {Set<string>}
 */
function parseAllowedOrigins() {
  const raw = process.env.CORS_ALLOWED_ORIGINS || '';

  if (!raw.trim()) {
    logger.warn('CORS_ALLOWED_ORIGINS no configurado. CORS bloqueará todas las solicitudes cross-origin.', {
      recommendation: 'Configurar CORS_ALLOWED_ORIGINS en variables de entorno',
    });
    return new Set();
  }

  const origins = raw
    .split(',')
    .map((o) => o.trim())
    .filter((o) => {
      // Validar que cada origen sea una URL HTTPS válida (no permitir HTTP en producción)
      if (!o.startsWith('https://') && process.env.NODE_ENV === 'production') {
        logger.error(`Origen CORS rechazado: "${o}" no usa HTTPS. En producción solo se permiten orígenes HTTPS.`);
        return false;
      }
      if (o === '*') {
        // Wildcard NUNCA permitido — falla el proceso si alguien lo configura
        logger.error('CORS_ALLOWED_ORIGINS contiene "*". Esto es un riesgo de seguridad crítico. Proceso terminado.');
        process.exit(1); // Falla rápido: configuración insegura no debe correr en producción
      }
      return true;
    });

  logger.info(`CORS configurado con ${origins.length} origen(es) permitido(s)`, {
    origins: origins.map((o) => o.substring(0, 50)), // Log sin exponer URLs completas
  });

  return new Set(origins);
}

// Cache de orígenes para no re-parsear en cada request
const ALLOWED_ORIGINS = parseAllowedOrigins();

/**
 * Función validadora de origen para el módulo cors.
 * Se ejecuta en cada request con header Origin.
 *
 * @param {string|null|undefined} origin - Valor del header Origin del request
 * @param {Function} callback - (error, allow: boolean)
 */
function validateOrigin(origin, callback) {
  // Sin header Origin: request directo (curl, Postman, app móvil nativa, Raspberry Pi)
  // Permitir: CORS solo aplica a navegadores; sin Origin es un cliente legítimo no-browser.
  if (!origin) {
    return callback(null, true);
  }

  // Origen en lista blanca: permitir
  if (ALLOWED_ORIGINS.has(origin)) {
    return callback(null, true);
  }

  // Origen no autorizado: rechazar
  logger.warn('Solicitud CORS rechazada', {
    event: 'CORS_BLOCKED',
    origin: origin.substring(0, 100), // Truncar para seguridad
    allowedCount: ALLOWED_ORIGINS.size,
  });

  // Retornar error personalizado (el módulo cors lo convierte en 403)
  const err = new Error(`Origen no autorizado: ${origin.substring(0, 50)}`);
  err.status = 403;
  return callback(err);
}

/**
 * Construye la configuración CORS para microservicios GymPro.
 *
 * @param {object} [options]
 * @param {string[]} [options.extraMethods=[]]      - Métodos HTTP adicionales a permitir
 * @param {boolean} [options.allowCredentials=true] - Permitir cookies/auth headers
 * @returns {import('express').RequestHandler}
 */
function buildCorsMiddleware({ extraMethods = [], allowCredentials = true } = {}) {
  const allowedMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', ...extraMethods];

  return cors({
    origin: validateOrigin,

    // Métodos HTTP permitidos. HEAD y OPTIONS siempre necesarios para preflight.
    methods: allowedMethods,

    // Headers que el cliente puede enviar al servidor.
    // OWASP: Lista explícita — nunca usar '*' con credentials.
    allowedHeaders: [
      'Content-Type',       // Siempre requerido para POST/PUT
      'Authorization',      // JWT Bearer token
      'X-Request-ID',       // ID de correlación de logs
      'X-Device-ID',        // ID del dispositivo físico (torniquete)
      'Accept',
      'Accept-Language',
      'Cache-Control',
    ],

    // Headers que el cliente puede leer en la respuesta.
    // Por defecto, el navegador solo expone headers "safe" (Content-Type, etc.)
    exposedHeaders: [
      'X-Request-ID',       // Para correlación de logs del lado cliente
      'X-RateLimit-Limit',  // Info de rate limit (RFC 6585)
      'X-RateLimit-Remaining',
      'X-RateLimit-Reset',
      'Retry-After',        // Cuándo reintentar tras 429
    ],

    // credentials: true es necesario para que el navegador envíe cookies
    // y el header Authorization en requests cross-origin.
    // IMPORTANTE: Con credentials:true, origin NO puede ser '*'.
    credentials: allowCredentials,

    // Tiempo que el navegador puede cachear el resultado del preflight (OPTIONS).
    // 86400 = 24 horas. Reduce el número de requests OPTIONS.
    maxAge: 86_400,

    // Responder automáticamente a requests OPTIONS (preflight).
    // El servidor responde 204 No Content al preflight sin pasar al siguiente middleware.
    preflightContinue: false,
    optionsSuccessStatus: 204,
  });
}

module.exports = { buildCorsMiddleware, ALLOWED_ORIGINS };
