/**
 * @file services/ai-service/src/main.js
 * @description Entry point del ai-service.
 *
 * ⚠️  PARTICULARIDADES CRÍTICAS:
 *
 * 1. SSE STREAMING (Server-Sent Events):
 *    El endpoint de chat usa SSE para transmitir la respuesta del LLM token a token.
 *    Los middlewares de compresión (gzip) y buffering deben estar deshabilitados
 *    para esta ruta, de lo contrario el stream se bloquea hasta completarse.
 *    Express no comprime rutas con Content-Type: text/event-stream por defecto.
 *
 * 2. RATE LIMITING ULTRA-ESTRICTO:
 *    Cada request al LLM puede costar entre $0.001 y $0.05 según el modelo.
 *    Un límite de 10 req/min por usuario previene abusos costosos.
 *    Se usa un rate limiter DIARIO adicional (50 req/día por usuario).
 *
 * 3. TIMEOUT EXTENDIDO:
 *    Las respuestas de LLM pueden tomar 10-30 segundos. El timeout del servidor
 *    debe extenderse para rutas de chat. Configurado por ruta, no globalmente.
 *
 * 4. CONTEXT INJECTION:
 *    Antes de llamar al LLM, este servicio consulta fitness-service vía M2M
 *    para obtener el contexto del usuario (rutinas, progreso, objetivos).
 *    Esto es transparente para el cliente.
 */

'use strict';

const express = require('express');
const { createSecurityMiddleware }    = require('../../../packages_shared/security');
const { createAiRateLimiter,
        createUserRateLimiter }       = require('../../../packages_shared/security/rateLimiter');
const { createJwtVerifyMiddleware }   = require('../../../packages_shared/security/jwtVerify');

// ── Fail-fast ──────────────────────────────────────────────────────────────────
const REQUIRED_ENV = [
  'NODE_ENV', 'PORT',
  'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY',
  'JWT_SECRET', 'INTER_SERVICE_SECRET',
  'AI_PROVIDER',
];

// Validar que exista la API key del proveedor configurado
const provider = process.env.AI_PROVIDER?.toLowerCase();
if (provider === 'gemini' && !process.env.GEMINI_API_KEY) REQUIRED_ENV.push('GEMINI_API_KEY');
if (provider === 'openai' && !process.env.OPENAI_API_KEY) REQUIRED_ENV.push('OPENAI_API_KEY');

const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`[ai-service] Variables faltantes: ${missing.join(', ')}`);
  process.exit(1);
}

const chatRoutes           = require('./routes/chatRoutes');
const recommendationRoutes = require('./routes/recommendationRoutes');

async function bootstrap() {
  const app = express();
  app.set('trust proxy', 1);

  // ── Redis (obligatorio para ai-service: control de cuotas diarias) ─────────
  let redisClient = null;
  if (process.env.REDIS_URL) {
    const Redis = require('ioredis');
    redisClient = new Redis(process.env.REDIS_URL, {
      retryStrategy: (t) => Math.min(t * 100, 3000),
    });
    redisClient.on('error', (e) =>
      security.logger.error('Redis error — cuotas diarias de IA no disponibles', {
        error: e.message,
        impact: 'Rate limiting diario desactivado temporalmente',
      })
    );
  } else {
    console.warn('[ai-service] REDIS_URL no configurado. Las cuotas diarias no funcionarán correctamente.');
  }

  const security = createSecurityMiddleware({
    serviceName:    'ai-service',
    redisClient,
    maxPayloadSize: '20kb',     // Los mensajes de chat pueden incluir contexto extenso
    globalRateMax:  30,         // Muy estricto: cada request puede costar dinero
    isApiOnly:      true,
  });

  security.applyGlobal(app);

  // ── Exponer el cliente Redis a los controllers (caché de recomendaciones) ──
  app.use((req, _res, next) => {
    req.redisClient = redisClient;
    next();
  });

  // ── Health ─────────────────────────────────────────────────────────────────
  app.get('/health', (_req, res) =>
    res.json({
      success: true,
      data: {
        service:     'ai-service',
        status:      'healthy',
        uptime:      Math.floor(process.uptime()),
        aiProvider:  process.env.AI_PROVIDER,
        aiModel:     process.env.GEMINI_MODEL || process.env.OPENAI_MODEL,
        redisEnabled: !!redisClient,
      },
      error: null,
    })
  );

  // ── Rate limiters para IA (múltiples capas de protección de costos) ─────────
  // CAPA 1: Rate limit por minuto (previene ráfagas)
  const aiMinuteRateLimiter = createAiRateLimiter({
    redisClient,
    max:      parseInt(process.env.RATE_LIMIT_AI_CHAT_MAX || '10', 10),
    windowMs: 60_000,
    prefix:   'rl:ai:chat:min:',
  });

  // CAPA 2: Rate limit diario (control de costos mensual por usuario)
  // Ventana de 24 horas con máximo de 50 requests
  const aiDailyRateLimiter = createAiRateLimiter({
    redisClient,
    max:      parseInt(process.env.AI_REQUESTS_PER_USER_PER_DAY || '50', 10),
    windowMs: 24 * 60 * 60_000,  // 24 horas
    prefix:   'rl:ai:chat:day:',
  });

  // Rate limiter para recomendaciones (menos frecuentes que el chat)
  const recommendationRateLimiter = createUserRateLimiter({
    redisClient,
    max:      5,                 // 5 planes de entrenamiento al día por usuario
    windowMs: 24 * 60 * 60_000,
    prefix:   'rl:ai:recommend:day:',
  });

  const jwtVerify = createJwtVerifyMiddleware({ redisClient });

  // ── Rutas de chat con SSE (dos capas de rate limiting) ─────────────────────
  app.use('/api/v1/chat',
    jwtVerify,
    aiDailyRateLimiter,     // Primero el diario (ventana más grande)
    aiMinuteRateLimiter,    // Luego el por minuto (previene ráfagas)
    // Extender timeout SOLO para rutas de chat (LLM puede tardar 30s+)
    (req, res, next) => {
      req.setTimeout(120_000);   // 2 minutos máximo
      res.setTimeout(120_000);
      next();
    },
    chatRoutes
  );

  // ── Rutas de recomendaciones (planes de entrenamiento/nutrición) ───────────
  app.use('/api/v1/recommendations',
    jwtVerify,
    recommendationRateLimiter,
    (req, res, next) => {
      req.setTimeout(60_000);    // 1 minuto (generación de planes es más rápida)
      res.setTimeout(60_000);
      next();
    },
    recommendationRoutes
  );

  security.applyFinal(app);

  const PORT   = parseInt(process.env.PORT || '3005', 10);
  const server = app.listen(PORT, '0.0.0.0', () =>
    security.logger.info(`ai-service escuchando en :${PORT}`, {
      aiProvider:           process.env.AI_PROVIDER,
      model:                process.env.GEMINI_MODEL || process.env.OPENAI_MODEL,
      dailyLimitPerUser:    process.env.AI_REQUESTS_PER_USER_PER_DAY || '50',
      minuteLimitPerUser:   process.env.RATE_LIMIT_AI_CHAT_MAX || '10',
      redisEnabled:         !!redisClient,
    })
  );

  // El SSE mantiene conexiones largas abiertas — el timeout del servidor
  // HTTP base debe ser mayor que el timeout por ruta para no cortar streams.
  server.keepAliveTimeout = 125_000;  // 5s más que el timeout de ruta

  const shutdown = async (sig) => {
    security.logger.info(`${sig} recibido. Cerrando ai-service...`);
    // Nota: las conexiones SSE abiertas se interrumpirán al cerrar el servidor.
    // El cliente Flutter debe implementar reconexión automática (EventSource retry).
    server.close(async () => {
      if (redisClient) await redisClient.quit();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 15_000);  // Más tiempo para streams activos
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}

bootstrap().catch((err) => {
  console.error('[ai-service] Error fatal en arranque:', err.message);
  process.exit(1);
});
