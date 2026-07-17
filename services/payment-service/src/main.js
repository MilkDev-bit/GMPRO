/**
 * @file services/payment-service/src/main.js
 * @description Entry point del payment-service.
 *
 * ⚠️  PARTICULARIDAD CRÍTICA — WEBHOOKS DE STRIPE:
 *   El endpoint POST /webhooks/stripe DEBE recibir el body como Buffer raw
 *   (no como JSON parseado). Stripe firma el payload original con HMAC-SHA256
 *   y si Express parsea el JSON antes, la firma no coincide y stripe.webhooks
 *   .constructEvent() lanzará una excepción.
 *
 *   Solución: montar el body parser raw SOLO para la ruta del webhook,
 *   ANTES del body parser JSON global.
 *
 * Otras particularidades:
 *   • Rate limit más estricto (50 req/min global, 10 req/min usuario)
 *   • El endpoint de webhooks NO tiene JWT (Stripe lo firma con su propio secret)
 *   • El endpoint de /cash-payment está protegido por API Key (para recepción)
 *   • Todos los demás endpoints SÍ requieren JWT de usuario
 */

'use strict';

// ── 1. Cargar y validar entorno temprano ──────────────────────────────────────
require('./config/environment');

const express = require('express');
const { createSecurityMiddleware }    = require('../../../packages_shared/security');
const { createUserRateLimiter }       = require('../../../packages_shared/security/rateLimiter');
const { createJwtVerifyMiddleware }   = require('../../../packages_shared/security/jwtVerify');
const { requireApiKey }               = require('./middlewares/apiKeyAuth');

const subscriptionRoutes  = require('./routes/subscriptionRoutes');
const paymentRoutes       = require('./routes/paymentRoutes');
const cashPaymentRoutes   = require('./routes/cashPaymentRoutes');
const webhookRoutes       = require('./routes/webhookRoutes');
const { startCronDaemon } = require('./services/growthRetentionWorker');

async function bootstrap() {
  const app = express();
  app.set('trust proxy', 1);

  let redisClient = null;
  if (process.env.REDIS_URL) {
    const Redis = require('ioredis');
    redisClient = new Redis(process.env.REDIS_URL, {
      retryStrategy: (t) => Math.min(t * 100, 3000),
    });
    redisClient.on('error', (e) =>
      console.error('[payment-service] Redis error:', e.message));
  }

  const security = createSecurityMiddleware({
    serviceName:    'payment-service',
    redisClient,
    maxPayloadSize: '10kb',
    globalRateMax:  50,     // Estricto: operaciones financieras sensibles
    isApiOnly:      true,
  });

  // ── PASO CRÍTICO: Webhook de Stripe ANTES del body parser JSON ────────────
  // Este middleware captura el body raw para la ruta del webhook.
  // La función verify de express.raw() almacena el buffer en req.rawBody,
  // que webhookController.js usa para verificar la firma de Stripe.
  //
  // OWASP A08: Sin verificación de firma, cualquiera podría enviar eventos
  // falsos de "pago exitoso" y activar suscripciones sin pagar.
  app.use(
    '/api/v1/webhooks/stripe',
    express.raw({
      type:   'application/json',
      limit:  '1mb',          // Stripe puede enviar payloads grandes (lotes de eventos)
      verify: (req, _res, buf) => {
        // Almacenar el buffer raw para que webhookController lo use en constructEvent()
        req.rawBody = buf;
      },
    })
  );

  // ── Middlewares de seguridad globales (Helmet, CORS, RL, Sanitización) ────
  // Se aplican a TODAS las rutas excepto el webhook (que ya tiene su body parser)
  security.applyGlobal(app);

  // ── Health ─────────────────────────────────────────────────────────────────
  app.get('/health', (_req, res) =>
    res.json({
      success: true,
      data: { service: 'payment-service', status: 'healthy', uptime: Math.floor(process.uptime()) },
      error: null,
    })
  );

  // ── Rate limiters específicos ──────────────────────────────────────────────
  const paymentRateLimiter = createUserRateLimiter({
    redisClient,
    max:      10,       // Muy estricto: máx 10 operaciones de pago/minuto
    windowMs: 60_000,
    prefix:   'rl:payment:ops:',
  });

  const jwtVerify = createJwtVerifyMiddleware({ redisClient });

  // ── 1. Rutas de pagos en efectivo / recepción (API Key requerida, SIN JWT) ─
  // Se montan en ambas rutas para máxima flexibilidad con el frontend de panel
  app.use('/api/v1/cash-payment',
    requireApiKey,
    paymentRateLimiter,
    cashPaymentRoutes
  );
  app.use('/api/v1/payments/cash-payment',
    requireApiKey,
    paymentRateLimiter,
    cashPaymentRoutes
  );

  // ── 2. Rutas protegidas para miembros (JWT requerido) ──────────────────────
  app.use('/api/v1/subscriptions',
    jwtVerify,
    paymentRateLimiter,
    subscriptionRoutes
  );

  app.use('/api/v1/payments',
    jwtVerify,
    paymentRateLimiter,
    paymentRoutes
  );

  // ── 3. Ruta de webhook Stripe (SIN JWT ni API Key, autenticación por firma) ─
  // El body ya fue parseado como raw Buffer arriba en /api/v1/webhooks/stripe
  app.use('/api/v1/webhooks', webhookRoutes);

  // ── Manejo final de errores (cierra el ciclo de Express) ───────────────────
  security.applyFinal(app);

  const PORT   = parseInt(process.env.PORT || '3003', 10);
  const server = app.listen(PORT, '0.0.0.0', () => {
    security.logger.info(`payment-service escuchando en :${PORT}`, {
      stripeMode:   process.env.STRIPE_SECRET_KEY?.startsWith('sk_live') ? 'PRODUCCIÓN' : 'TEST',
      redisEnabled: !!redisClient,
    });
    // Iniciar tarea Cron de Crecimiento y Retención en segundo plano
    startCronDaemon(parseInt(process.env.GROWTH_CRON_INTERVAL_MINUTES || '360', 10));
  });

  const shutdown = async (sig) => {
    security.logger.info(`${sig} recibido. Cerrando payment-service...`);
    server.close(async () => {
      if (redisClient) await redisClient.quit();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}

bootstrap().catch((err) => {
  console.error('[payment-service] Error fatal en arranque:', err.message);
  process.exit(1);
});
