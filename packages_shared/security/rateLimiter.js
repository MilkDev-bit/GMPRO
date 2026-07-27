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
 *
 * A10-1 (FAIL-CLOSED): el store principal es Redis (estado compartido entre
 * réplicas). Antes, si Redis no estaba disponible, se caía SILENCIOSAMENTE a
 * MemoryStore por-proceso → el límite se multiplicaba por réplica (fail-open) y
 * la protección anti-fuerza-bruta se debilitaba sin que nadie lo notara. Ahora:
 *   • En PRODUCCIÓN sin Redis → NO hay MemoryStore: el endpoint afectado responde
 *     503 (fail-closed) y se emite el evento RATE_LIMITER_STORE_UNAVAILABLE para
 *     alertar. /health y /ready NO se bloquean → el servicio sigue vivo (no es un
 *     apagón total, solo se cierra el endpoint que no puede aplicar el límite).
 *   • Error de Redis EN RUNTIME → `passOnStoreError: false` (fail-closed): la
 *     request no evade el límite (se corta con error, no se deja pasar).
 *   • En DESARROLLO sin Redis → MemoryStore (una sola instancia; cómodo y seguro).
 */

'use strict';

const { rateLimit } = require('express-rate-limit');
const { RedisStore }  = require('rate-limit-redis');
const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('rate-limiter');

const isProduction = () => process.env.NODE_ENV === 'production';

// ─── Resolución de IP real detrás de proxies ───────────────────────────────────
// Usa req.ip, que respeta `app.set('trust proxy', 1)` (configurado en el main.js
// de los 5 servicios). Con 1 hop de confianza, Express toma la IP que el edge de
// Railway añade a X-Forwarded-For y descarta lo que el cliente haya puesto.
//
// ┌─ VULNERABILIDAD CORREGIDA (CWE-348: Use of Less Trusted Source) ───────────┐
// │ El código anterior hacía `x-forwarded-for.split(',')[0]`, es decir tomaba  │
// │ el valor MÁS A LA IZQUIERDA del header. Ese extremo lo controla el cliente:│
// │ Railway ANEXA la IP real a la derecha → `XFF: <falsa-cliente>, <ip-real>`. │
// │ Tomar [0] devolvía la IP falsa, permitiendo evadir el rate limiter por IP  │
// │ (fuerza bruta de login, DoS) simplemente rotando el header en cada request.│
// │ req.ip con trust proxy=1 NO es falsificable de esta forma.                 │
// └────────────────────────────────────────────────────────────────────────────┘
//
// NOTA DE DESPLIEGUE: la corrección DEPENDE de que 'trust proxy' esté fijado en
// EXACTAMENTE el nº de proxies delante (1 en Railway). Si se añade otro proxy o
// CDN por delante, hay que subir ese número; si el servicio se expusiera SIN
// proxy, 'trust proxy' debe ser false (si no, req.ip volvería a ser spoofeable).
const getRealIp = (req) => req.ip || 'unknown';

// ─── Extractor de User ID desde JWT ya verificado ─────────────────────────────
const getUserIdentifier = (req) => {
  // req.user.id es inyectado por el middleware jwtVerify.js. Este extractor
  // SOLO devuelve el id de usuario si el JWT ya fue verificado ANTES en la
  // cadena; de lo contrario cae a IP.
  if (req.user?.id) return `usr:${req.user.id}`;
  return `ip:${getRealIp(req)}`;
};

/**
 * Configura un RedisStore si hay cliente Redis; si no, retorna null.
 * El manejo del caso null (fail-closed en prod / MemoryStore en dev) lo hace
 * `makeLimiter`, no este helper.
 * @returns {RedisStore|null}
 */
function buildRedisStore(redisClient, prefix) {
  if (!redisClient) return null;
  return new RedisStore({
    sendCommand: (...args) => redisClient.call(...args),
    prefix, // Previene colisiones entre limitadores distintos en la misma DB Redis
  });
}

// Throttle del log de "store no disponible" para no saturar (1 vez / 30s / prefijo).
const _lastUnavailableLog = new Map();
function logStoreUnavailable(prefix, extra = {}) {
  const now = Date.now();
  const last = _lastUnavailableLog.get(prefix) || 0;
  if (now - last < 30_000) return;
  _lastUnavailableLog.set(prefix, now);
  logger.error('Rate limiter sin store Redis → fail-closed (endpoint no disponible)', {
    event: 'RATE_LIMITER_STORE_UNAVAILABLE',
    prefix,
    ...extra,
  });
}

/**
 * Middleware fail-closed: se usa en PRODUCCIÓN cuando no hay store Redis. Responde
 * 503 en los endpoints afectados (para NO evadir el límite) pero deja pasar
 * /health y /ready → el orquestador ve el servicio vivo y no lo mata en cascada.
 */
function failClosedMiddleware(prefix) {
  return (req, res, next) => {
    if (req.path === '/health' || req.path === '/ready') return next();
    logStoreUnavailable(prefix, { path: req.path, method: req.method });
    return res.status(503).json({
      success: false,
      data: null,
      error: 'Servicio temporalmente no disponible (control de tasa). Reintenta en unos momentos.',
      retryAfter: 30,
    });
  };
}

/**
 * Fábrica central: construye el limitador con la política de A10-1.
 * @param {object} rlConfig  - config de express-rate-limit (sin `store`).
 * @param {import('ioredis').Redis|null} redisClient
 * @param {string} prefix
 * @returns {import('express').RequestHandler}
 */
function makeLimiter(rlConfig, redisClient, prefix) {
  const store = buildRedisStore(redisClient, prefix);

  if (!store) {
    if (isProduction()) {
      // Sin Redis en prod → fail-closed (no MemoryStore silencioso).
      logStoreUnavailable(prefix, { phase: 'startup' });
      return failClosedMiddleware(prefix);
    }
    logger.warn('Redis no configurado; usando MemoryStore (solo desarrollo).', { prefix });
  }

  return rateLimit({
    ...rlConfig,
    // A10-1: ante un error del store en runtime, NO dejar pasar la request
    // (evita que una caída de Redis abra un bypass del límite).
    passOnStoreError: false,
    ...(store ? { store } : {}),
  });
}

/**
 * Manejador de respuesta estándar cuando se supera el límite.
 */
function rateLimitHandler(req, res, _next, options) {
  const identifier = getUserIdentifier(req);

  logger.warn('Rate limit alcanzado', {
    event: 'RATE_LIMIT_EXCEEDED',
    identifier: identifier.substring(0, 50),
    path: req.path,
    method: req.method,
    userAgent: req.headers['user-agent']?.substring(0, 200),
    retryAfter: Math.ceil(options.windowMs / 1000),
  });

  res.status(429).json({
    success: false,
    data: null,
    error: `Demasiadas solicitudes. Intenta de nuevo en ${Math.ceil(options.windowMs / 60000)} minutos.`,
    retryAfter: Math.ceil(options.windowMs / 1000),
  });
}

/**
 * Limitador GLOBAL por IP para endpoints no autenticados (DoS/scraping).
 */
function createIpRateLimiter({ redisClient, max = 100, windowMs = 60_000, prefix = 'rl:global:' } = {}) {
  return makeLimiter({
    windowMs,
    max,
    keyGenerator: getRealIp,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: rateLimitHandler,
    skip: (req) => req.path === '/health' || req.path === '/ready',
  }, redisClient, prefix);
}

/**
 * Limitador ESTRICTO por IP para login/registro (fuerza bruta, OWASP A07).
 */
function createAuthRateLimiter({ redisClient, max = 5, windowMs = 15 * 60_000, prefix = 'rl:auth:' } = {}) {
  return makeLimiter({
    windowMs,
    max,
    keyGenerator: getRealIp,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    // Cuenta SOLO los intentos fallidos: un login correcto no penaliza.
    skipSuccessfulRequests: true,
    handler: rateLimitHandler,
  }, redisClient, prefix);
}

/**
 * Limitador por USUARIO AUTENTICADO (JWT user ID). OWASP A04.
 */
function createUserRateLimiter({ redisClient, max = 200, windowMs = 60_000, prefix = 'rl:user:' } = {}) {
  return makeLimiter({
    windowMs,
    max,
    keyGenerator: getUserIdentifier,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: rateLimitHandler,
    skip: (req) => req.path === '/health',
  }, redisClient, prefix);
}

/**
 * Limitador ULTRA-ESTRICTO para IA (control de costos LLM).
 */
function createAiRateLimiter({ redisClient, max = 10, windowMs = 60_000, prefix = 'rl:ai:' } = {}) {
  return makeLimiter({
    windowMs,
    max,
    keyGenerator: getUserIdentifier,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: rateLimitHandler,
  }, redisClient, prefix);
}

/**
 * Limitador POR CUENTA (keyed por email del body) contra fuerza bruta DISTRIBUIDA.
 * skipSuccessfulRequests: solo cuenta fallos → el dueño legítimo nunca se bloquea.
 */
function createAccountRateLimiter({ redisClient, max = 10, windowMs = 60 * 60_000, prefix = 'rl:account:', field = 'email' } = {}) {
  return makeLimiter({
    windowMs,
    max,
    keyGenerator: (req) => {
      const v = String(req.body?.[field] || '').trim().toLowerCase();
      return v ? `acct:${v}` : `ip:${getRealIp(req)}`;
    },
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    handler: rateLimitHandler,
  }, redisClient, prefix);
}

module.exports = {
  createIpRateLimiter,
  createAuthRateLimiter,
  createUserRateLimiter,
  createAiRateLimiter,
  createAccountRateLimiter,
  // Exportados para tests:
  _internal: { makeLimiter, failClosedMiddleware, buildRedisStore },
};
