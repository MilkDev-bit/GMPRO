/**
 * @file packages_shared/security/index.js
 * @description Punto de entrada del módulo de seguridad compartido.
 *
 * Exporta una función factory `createSecurityMiddleware` que ensambla
 * y retorna todos los middlewares de seguridad en el orden correcto.
 *
 * ORDEN DE MIDDLEWARES (crítico para que funcionen correctamente):
 *
 *   1. Helmet        → Headers de seguridad (antes de todo)
 *   2. CORS          → Validación de origen (antes de parsear body)
 *   3. Rate Limit IP → Rechazar IPs abusivas (antes de procesar)
 *   4. Body Parsing  → express.json() — con límite de tamaño
 *   5. HPP           → Limpiar parámetros duplicados (después de parsing)
 *   6. Sanitización  → Limpiar XSS/injection (después de parsing)
 *   7. [Rutas]       → Lógica de negocio
 *   8. 404 Handler   → Rutas no encontradas
 *   9. Error Handler → Último siempre
 *
 * Uso en cada microservicio (src/main.js):
 *
 *   const { createSecurityMiddleware } = require('@gympro/shared/security');
 *   const security = createSecurityMiddleware({ serviceName: 'auth-service', redisClient });
 *   security.applyGlobal(app);     // Aplica middlewares globales
 *   // ... montar rutas ...
 *   security.applyFinal(app);      // Aplica 404 y errorHandler AL FINAL
 */

'use strict';

const express = require('express');

const { buildHelmetMiddleware, additionalSecurityHeaders } = require('./helmetConfig');
const { buildCorsMiddleware }                               = require('./corsConfig');
const { createIpRateLimiter }                              = require('./rateLimiter');
const { createInputSanitizer, createPayloadSizeLimiter, createHppProtection } = require('./inputSanitizer');
const { createErrorHandler, createNotFoundHandler }        = require('./errorHandler');
const { createServiceLogger }                              = require('./logger');

/**
 * @typedef {object} SecurityOptions
 * @property {string}                         serviceName        - Nombre del microservicio
 * @property {import('ioredis').Redis|null}    [redisClient]      - Cliente Redis para rate limiting
 * @property {string}                         [maxPayloadSize]   - Tamaño máximo del body (default: '10kb')
 * @property {number}                         [globalRateMax]    - Max requests por IP por minuto
 * @property {boolean}                        [isApiOnly]        - API pura sin HTML (default: true)
 * @property {string[]}                       [hppWhitelist]     - Params que permiten arrays
 */

/**
 * Factory que crea y configura todos los middlewares de seguridad.
 *
 * @param {SecurityOptions} options
 * @returns {{ applyGlobal: Function, applyFinal: Function, logger: object }}
 */
function createSecurityMiddleware(options = {}) {
  const {
    serviceName = 'unknown-service',
    redisClient = null,
    maxPayloadSize = '10kb',
    globalRateMax = 100,
    isApiOnly = true,
    hppWhitelist = [],
  } = options;

  const logger = createServiceLogger(serviceName);

  // Instanciar middlewares una sola vez (singleton por proceso)
  const helmetMiddlewares = buildHelmetMiddleware({ isApiOnly });
  const corsMiddleware    = buildCorsMiddleware();
  const ipRateLimiter    = createIpRateLimiter({ redisClient, max: globalRateMax });
  const hppProtection    = createHppProtection(hppWhitelist);
  const inputSanitizer   = createInputSanitizer({ blockOnThreat: true });
  const payloadLimiter   = createPayloadSizeLimiter(maxPayloadSize);
  const notFoundHandler  = createNotFoundHandler();
  const errorHandler     = createErrorHandler(serviceName);

  logger.info(`Módulo de seguridad inicializado para ${serviceName}`, {
    redisEnabled: !!redisClient,
    maxPayloadSize,
    globalRateMax,
  });

  return {
    /**
     * Aplica los middlewares de seguridad GLOBALES a la app Express.
     * Llamar ANTES de montar cualquier ruta.
     *
     * @param {import('express').Application} app
     */
    applyGlobal(app) {
      // 1. Cabeceras de seguridad Helmet (lo más temprano posible)
      app.use(helmetMiddlewares);
      app.use(additionalSecurityHeaders());

      // 2. CORS — antes de parsear el body (preflight no tiene body)
      app.use(corsMiddleware);

      // 3. Rate limiting por IP — rechazar antes de procesar cualquier cosa
      app.use(ipRateLimiter);

      // 4. Límite de tamaño del body — antes del parser (más eficiente)
      app.use(payloadLimiter);

      // 5. Parsers de body con límite adicional
      app.use(express.json({
        limit: maxPayloadSize,
        // strict: true rechaza cualquier JSON que no sea objeto/array en el root
        strict: true,
      }));
      app.use(express.urlencoded({
        extended: false,  // false = qs simple, sin objetos anidados (más seguro)
        limit: maxPayloadSize,
      }));

      // 6. Prevención de Parameter Pollution — después de parsear
      app.use(hppProtection);

      // 7. Sanitización de inputs — última línea de defensa antes de las rutas
      app.use(inputSanitizer);

      logger.info('Middlewares de seguridad globales aplicados');
    },

    /**
     * Aplica los middlewares FINALES (404 y error handler).
     * Llamar DESPUÉS de montar todas las rutas.
     *
     * @param {import('express').Application} app
     */
    applyFinal(app) {
      // 404: Rutas no encontradas
      app.use(notFoundHandler);

      // Error handler: SIEMPRE el último middleware (4 parámetros)
      app.use(errorHandler);

      logger.info('Middlewares finales (404/error handler) aplicados');
    },

    // Exponer logger para uso en el servicio
    logger,
  };
}

module.exports = {
  createSecurityMiddleware,
  // Re-exportar módulos individuales para uso granular
  rateLimiter:   require('./rateLimiter'),
  helmetConfig:  require('./helmetConfig'),
  corsConfig:    require('./corsConfig'),
  inputSanitizer: require('./inputSanitizer'),
  errorHandler:  require('./errorHandler'),
  logger:        require('./logger'),
};
