/**
 * @file packages_shared/security/rateLimiter.js
 * @description Rate Limiting dual: por IP y por token JWT de usuario.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP Top 10 Mitigaciones:                                         ║
 * ║  • A07:2021 — Identification and Authentication Failures            ║
 * ║    → Límite de intentos de login previene ataques de fuerza bruta   ║
 * ║  • A04:2021 — Insecure Design                                       ║
 * ║    → Rate limit por JWT evita que una cuenta comprometida           ║
 * ║      abuse la API aunque cambie de IP (VPN/proxy)                   ║
 * ║  • A05:2021 — Security Misconfiguration                             ║
 * ║    → Skip list para /health evita falsos positivos en healthchecks  ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * Arquitectura de Rate Limiting:
 *   1. CAPA IP:    Limita requests por dirección IP (protege de DDoS y scraping)
 *   2. CAPA JWT:   Limita requests por usuario autenticado (abuso de cuenta)
 *   3. FALLBACK:   Si Redis no está disponible, usa MemoryStore en proceso
 *                  (acepta falsos negativos en el arranque; prefiere disponibilidad)
 */

'use strict';

const { rateLimit } = require('express-rate-limit');
const { RedisStore }  = require('rate-limit-redis');
const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('rate-limiter');

// ─── Resolución de IP real detrás de proxies ───────────────────────────────────
// Railway y la mayoría de PaaS colocan el IP real en X-Forwarded-For.
// PELIGRO: Solo confiar en este header si el servidor está DETRÁS de un proxy
// conocido. Si se expone directamente a internet, un cliente puede falsificar este header.
const getRealIp = (req) => {
  // Confiar solo en el primer valor de X-Forwarded-For (más cercano al cliente)
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }
  return req.ip || req.connection.remoteAddress;
};

// ─── Extractor de User ID desde JWT ya verificado ─────────────────────────────
// Este extractor se usa DESPUÉS del middleware de verificación JWT.
// Si el token no fue verificado, req.user será undefined → fallback a IP.
const getUserIdentifier = (req) => {
  // req.user.id es inyectado por el middleware jwtVerify.js
  return req.user?.id || getRealIp(req);
};

/**
 * Configura una instancia de RedisStore si hay conexión Redis disponible.
 * Retorna null si Redis no está configurado (se usará MemoryStore como fallback).
 *
 * @param {import('ioredis').Redis|null} redisClient - Cliente Redis ya conectado
 * @param {string} prefix - Prefijo de clave para este limitador (ej: 'rl:login:')
 * @returns {RedisStore|null}
 */
function buildRedisStore(redisClient, prefix) {
  if (!redisClient) {
    logger.warn('Redis no configurado para rate limiting. Usando MemoryStore.', {
      note: 'MemoryStore no comparte estado entre instancias — usar solo en desarrollo',
    });
    return null; // express-rate-limit usará MemoryStore por defecto
  }

  return new RedisStore({
    // sendCommand: adaptador que conecta rate-limit-redis con ioredis
    sendCommand: (...args) => redisClient.call(...args),
    prefix, // Previene colisiones entre limitadores distintos en la misma DB Redis
  });
}

/**
 * Manejador de respuesta estándar cuando se supera el límite.
 * OWASP: No revelar información de implementación interna en el mensaje.
 * Sí revelar el tiempo de espera para mejorar UX (no es info sensible).
 */
function rateLimitHandler(req, res, _next, options) {
  const identifier = getUserIdentifier(req);

  // Log de seguridad: registro del intento bloqueado para análisis SIEM
  logger.warn('Rate limit alcanzado', {
    event: 'RATE_LIMIT_EXCEEDED',
    identifier: identifier.substring(0, 50), // Truncar para no saturar logs
    path: req.path,
    method: req.method,
    userAgent: req.headers['user-agent']?.substring(0, 200),
    retryAfter: Math.ceil(options.windowMs / 1000),
  });

  // Respuesta estándar de la API (mismo formato que apiResponse.d.ts)
  res.status(429).json({
    success: false,
    data: null,
    error: `Demasiadas solicitudes. Intenta de nuevo en ${Math.ceil(options.windowMs / 60000)} minutos.`,
    retryAfter: Math.ceil(options.windowMs / 1000),
  });
}

/**
 * Crea el limitador GLOBAL por IP para endpoints no autenticados.
 * Se aplica como primer middleware en la cadena (antes de parsear el body).
 *
 * Propósito: Prevenir DoS y reducir carga de procesamiento para IPs abusivas.
 *
 * @param {object} options
 * @param {import('ioredis').Redis|null} options.redisClient
 * @param {number} [options.max=100]              - Máximo de requests permitidos
 * @param {number} [options.windowMs=60000]       - Ventana de tiempo en ms
 * @param {string} [options.prefix='rl:global:']  - Prefijo de clave Redis
 * @returns {import('express').RequestHandler}
 */
function createIpRateLimiter({ redisClient, max = 100, windowMs = 60_000, prefix = 'rl:global:' } = {}) {
  const store = buildRedisStore(redisClient, prefix);

  return rateLimit({
    windowMs,
    max,
    // Identificar al cliente por IP real (no por IP del proxy de Railway)
    keyGenerator: getRealIp,
    // Incluir headers estándar RFC 6585 en la respuesta
    // X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
    standardHeaders: 'draft-7',
    // Deshabilitar headers legacy (X-RateLimit-*) para evitar info redundante
    legacyHeaders: false,
    // No contar las respuestas exitosas hacia el límite (solo errores)
    // skipSuccessfulRequests: false, ← contar TODOS los requests (default)
    handler: rateLimitHandler,
    // Omitir rutas de salud para no bloquear healthchecks de Railway/Docker
    skip: (req) => req.path === '/health' || req.path === '/ready',
    ...(store ? { store } : {}),
  });
}

/**
 * Crea el limitador ESTRICTO por JWT para endpoints de login/registro.
 * Se aplica SOLO en rutas de autenticación (mayor riesgo de fuerza bruta).
 *
 * OWASP A07: Previene ataques de fuerza bruta sobre contraseñas.
 * El límite es por IP (antes de tener JWT) ya que el atacante no tiene token.
 *
 * @param {object} options
 * @param {import('ioredis').Redis|null} options.redisClient
 * @param {number} [options.max=5]                    - Intentos de login permitidos
 * @param {number} [options.windowMs=900000]          - 15 minutos por defecto
 * @param {string} [options.prefix='rl:auth:']
 * @returns {import('express').RequestHandler}
 */
function createAuthRateLimiter({ redisClient, max = 5, windowMs = 15 * 60_000, prefix = 'rl:auth:' } = {}) {
  const store = buildRedisStore(redisClient, prefix);

  return rateLimit({
    windowMs,
    max,
    keyGenerator: getRealIp,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    // Contar SOLO los intentos fallidos (4xx/5xx). Los logins exitosos no penalizan.
    // Esto mejora UX: usuarios legítimos no se bloquean por usar bien el servicio.
    skipSuccessfulRequests: true,
    handler: rateLimitHandler,
    ...(store ? { store } : {}),
  });
}

/**
 * Crea el limitador por USUARIO AUTENTICADO (basado en JWT user ID).
 * Se aplica en endpoints protegidos DESPUÉS de verificar el JWT.
 *
 * OWASP A04: Una cuenta comprometida con VPN no puede abusar la API
 * cambiando de IP, ya que el limitador usa el user ID del token.
 *
 * @param {object} options
 * @param {import('ioredis').Redis|null} options.redisClient
 * @param {number} [options.max=200]                  - Requests por usuario por ventana
 * @param {number} [options.windowMs=60000]           - 1 minuto por defecto
 * @param {string} [options.prefix='rl:user:']
 * @returns {import('express').RequestHandler}
 */
function createUserRateLimiter({ redisClient, max = 200, windowMs = 60_000, prefix = 'rl:user:' } = {}) {
  const store = buildRedisStore(redisClient, prefix);

  return rateLimit({
    windowMs,
    max,
    // Usa user ID del JWT verificado; si no hay JWT, usa IP (failsafe)
    keyGenerator: getUserIdentifier,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: rateLimitHandler,
    skip: (req) => req.path === '/health',
    ...(store ? { store } : {}),
  });
}

/**
 * Crea el limitador ULTRA-ESTRICTO para endpoints de IA (control de costos).
 * Limita por usuario para evitar abuso de tokens de LLM.
 *
 * @param {object} options
 * @param {import('ioredis').Redis|null} options.redisClient
 * @param {number} [options.max=10]                   - Requests de IA por minuto
 * @param {number} [options.windowMs=60000]
 * @param {string} [options.prefix='rl:ai:']
 * @returns {import('express').RequestHandler}
 */
function createAiRateLimiter({ redisClient, max = 10, windowMs = 60_000, prefix = 'rl:ai:' } = {}) {
  const store = buildRedisStore(redisClient, prefix);

  return rateLimit({
    windowMs,
    max,
    keyGenerator: getUserIdentifier,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: rateLimitHandler,
    ...(store ? { store } : {}),
  });
}

module.exports = {
  createIpRateLimiter,
  createAuthRateLimiter,
  createUserRateLimiter,
  createAiRateLimiter,
};
