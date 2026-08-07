/**
 * @file services/fitness-service/src/main.js
 * @description Entry point del fitness-service.
 *
 * Particularidades:
 *   • Redis obligatorio para cachear el catálogo de ejercicios (evita round-trips a Supabase)
 *   • Paginación en todos los endpoints de listado (previene consultas masivas)
 *   • Rate limit generoso (200 req/min): los usuarios consultan rutinas frecuentemente
 *   • Soporte de whitelist HPP para parámetros de filtrado que admiten arrays
 *     (ej: ?muscleGroup=pecho&muscleGroup=hombro → array legítimo)
 */

'use strict';

const express = require('express');
const { createSecurityMiddleware }    = require('../../../packages_shared/security');
const { createUserRateLimiter }       = require('../../../packages_shared/security/rateLimiter');
const { createJwtVerifyMiddleware,
        createInterServiceAuthMiddleware } = require('../../../packages_shared/security/jwtVerify');

// ── Fail-fast ──────────────────────────────────────────────────────────────────
const REQUIRED_ENV = [
  'NODE_ENV', 'PORT',
  'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY',
  'INTER_SERVICE_SECRET',
];
const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`[fitness-service] Variables faltantes: ${missing.join(', ')}`);
  process.exit(1);
}

const routineRoutes  = require('./routes/routineRoutes');
const exerciseRoutes = require('./routes/exerciseRoutes');
const progressRoutes = require('./routes/progressRoutes');
const foodRoutes     = require('./routes/foodRoutes');

async function bootstrap() {
  const app = express();
  app.set('trust proxy', 1);

  // ── Redis (recomendado: cachea catálogo de ejercicios) ─────────────────────
  let redisClient = null;
  if (process.env.REDIS_URL) {
    const Redis = require('ioredis');
    redisClient = new Redis(process.env.REDIS_URL, {
      retryStrategy: (t) => Math.min(t * 100, 3000),
    });
    redisClient.on('connect', () =>
      security.logger.info('Redis conectado — caché de ejercicios activo'));
    redisClient.on('error', (e) =>
      security.logger.warn('Redis error (caché desactivado, continuando sin caché)', {
        error: e.message,
      })
    );
  }

  const security = createSecurityMiddleware({
    serviceName:    'fitness-service',
    redisClient,
    maxPayloadSize: '50kb',     // Rutinas pueden ser payloads grandes (muchos ejercicios)
    globalRateMax:  200,        // Generoso: los usuarios consultan rutinas todo el tiempo
    isApiOnly:      true,
    // HPP whitelist: estos parámetros SÍ pueden repetirse (filtros múltiples)
    hppWhitelist:   ['muscleGroup', 'equipment', 'difficulty', 'tag'],
  });

  security.applyGlobal(app);

  // ── Health ─────────────────────────────────────────────────────────────────
  app.get('/health', (_req, res) =>
    res.json({
      success: true,
      data: {
        service:      'fitness-service',
        status:       'healthy',
        uptime:       Math.floor(process.uptime()),
        cacheEnabled: !!redisClient,
      },
      error: null,
    })
  );

  // ── Rate limiters ──────────────────────────────────────────────────────────
  // Rate limiter para escrituras (guardar progreso, crear rutinas)
  const writeRateLimiter = createUserRateLimiter({
    redisClient,
    max:      60,       // 60 escrituras/min por usuario — más que suficiente
    windowMs: 60_000,
    prefix:   'rl:fitness:write:',
  });

  const jwtVerify = createJwtVerifyMiddleware({ redisClient });
  const m2mAuth   = createInterServiceAuthMiddleware(); // Para llamadas del ai-service

  // ── Rutas de usuario (JWT requerido) ──────────────────────────────────────
  app.use('/api/v1/routines',
    jwtVerify,
    writeRateLimiter,   // Escrituras limitadas
    routineRoutes
  );

  // Ejercicios: lectura intensa, caché de Redis, rate limit global es suficiente
  app.use('/api/v1/exercises',
    jwtVerify,
    exerciseRoutes      // Sin rate limiter adicional (ya cubierto por el global)
  );

  app.use('/api/v1/progress',
    jwtVerify,
    writeRateLimiter,
    progressRoutes
  );

  // Alimentos de Open Food Facts: lectura para personalización de dieta
  app.use('/api/v1/foods',
    jwtVerify,
    foodRoutes
  );

  // Diario nutricional real: consumo diario de calorías/macros + agua bebida
  app.use('/api/v1/nutrition',
    jwtVerify,
    writeRateLimiter,
    require('./routes/nutritionRoutes')
  );

  // ── Ruta interna M2M (ai-service consulta datos del usuario) ──────────────
  // El ai-service necesita datos de fitness para construir el contexto del prompt
  app.use('/api/v1/internal',
    m2mAuth,
    require('./routes/internalRoutes')
  );

  security.applyFinal(app);

  // ── Worker de correos transaccionales (BullMQ) ────────────────────────────
  // Corre en el mismo proceso pero fuera del ciclo request/response: encolar es
  // instantáneo y la entrega (con reintentos) nunca bloquea al usuario.
  const { startEmailWorker, stopEmailWorker } = require('./services/email/emailWorker');
  const { closeQueue } = require('./services/email/emailQueue');
  startEmailWorker();

  const PORT   = parseInt(process.env.PORT || '3004', 10);
  const server = app.listen(PORT, '0.0.0.0', () =>
    security.logger.info(`fitness-service escuchando en :${PORT}`, {
      redisEnabled:   !!redisClient,
      cacheTtl:       process.env.EXERCISE_CATALOG_CACHE_TTL || '3600',
      hppWhitelist:   ['muscleGroup', 'equipment', 'difficulty', 'tag'],
      emailQueue:     !!process.env.REDIS_URL,
    })
  );

  const shutdown = async (sig) => {
    security.logger.info(`${sig} recibido. Cerrando fitness-service...`);
    server.close(async () => {
      // Esperar a que terminen los correos en vuelo antes de matar el proceso.
      await stopEmailWorker();
      await closeQueue();
      if (redisClient) await redisClient.quit();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}

bootstrap().catch((err) => {
  console.error('[fitness-service] Error fatal en arranque:', err.message);
  process.exit(1);
});
