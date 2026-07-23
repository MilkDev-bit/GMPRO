/**
 * @file services/access-service/src/main.js
 * @description Entry point del access-service.
 *
 * Particularidades de seguridad y concurrencia de este servicio:
 *   • Cifrado AES-256-GCM para generación de códigos QR de un solo uso (/generate-qr)
 *   • Mutex distribuido Redis + Check-and-Set atómico en DB contra Race Conditions en pases de una visita (/validate-ticket)
 *   • Rate limiters específicos y autenticación M2M (TURNSTILE_API_KEY) para hardware de torniquetes
 */

'use strict';

// ── 1. Cargar y validar entorno temprano ──────────────────────────────────────
const env = require('./config/environment');

const express = require('express');
const { createSecurityMiddleware }    = require('../../../packages_shared/security');
const { createUserRateLimiter }       = require('../../../packages_shared/security/rateLimiter');
const { createJwtVerifyMiddleware }   = require('../../../packages_shared/security/jwtVerify');
const { requireTurnstileApiKey }      = require('./middlewares/turnstileAuth');

const qrRoutes         = require('./routes/qrRoutes');
const createTicketRoutes = require('./routes/ticketRoutes'); // factory({ redisClient })
const accessRoutes     = require('./routes/accessRoutes');
const internalRoutes   = require('./routes/internalRoutes');
const zkAdmsRoutes     = require('./routes/zkAdmsRoutes');
const qrController     = require('./controllers/qrController');
const ticketController = require('./controllers/ticketController');


async function bootstrap() {
  const app = express();
  app.set('trust proxy', 1);

  let redisClient = null;
  if (process.env.REDIS_URL) {
    const Redis = require('ioredis');
    redisClient = new Redis(process.env.REDIS_URL, {
      retryStrategy: (t) => Math.min(t * 100, 3000),
      lazyConnect: false,
    });
    redisClient.on('error', (e) =>
      console.error('[access-service] Redis error:', e.message));
  }

  const security = createSecurityMiddleware({
    serviceName:    'access-service',
    redisClient,
    maxPayloadSize: '10kb',
    globalRateMax:  60,
    isApiOnly:      true,
  });

  security.applyGlobal(app);

  // ── Exponer el cliente Redis a los controllers vía req.redisClient ─────────
  // Los controllers (qr, ticket, internal) leen req.redisClient para caché de
  // vigencia y locks atómicos. Se inyecta una sola vez tras la seguridad global.
  app.use((req, _res, next) => {
    req.redisClient = redisClient;
    next();
  });

  // ── Health ────────────────────────────────────────────────────────────────
  app.get('/health', (_req, res) =>
    res.json({
      success: true,
      data: { service: 'access-service', status: 'healthy', uptime: Math.floor(process.uptime()) },
      error: null,
    })
  );

  // ── Rate limiters y Auth Middlewares ──────────────────────────────────────
  const qrRateLimiter = createUserRateLimiter({
    redisClient,
    // Máx 10 QRs/min por usuario. El QR rota con vigencia corta; generarlos
    // en ráfaga no es un uso legítimo. Devuelve 429 al superar el umbral.
    max:      env.RATE_LIMIT_QR_MAX,
    windowMs: 60_000,
    prefix:   'rl:access:qr:',
  });

  const validateRateLimiter = createUserRateLimiter({
    redisClient,
    max:      180,      // Hardware puede validar hasta 3 accesos/seg por torniquete
    windowMs: 60_000,
    prefix:   'rl:access:validate:',
  });

  const jwtVerify = createJwtVerifyMiddleware({ redisClient });

  // RBAC: /create-ticket es SOLO para personal interno (staff/admin). Los
  // socios ('miembro') usan /generate-qr, no emiten pases físicos. Este
  // verificador responde 403 si el rol no está autorizado.
  const staffOnlyVerify = createJwtVerifyMiddleware({
    redisClient,
    requiredRoles: env.STAFF_ROLES, // externalizado (STAFF_ROLES), fallback staff,admin
  });

  // Anti emisión masiva de pases: 30/min por usuario (staff), Redis-backed, 429.
  const ticketCreateRateLimiter = createUserRateLimiter({
    redisClient,
    max:      env.RATE_LIMIT_TICKET_MAX,
    windowMs: 60_000,
    prefix:   'rl:access:ticket:',
  });

  // ── 1. Endpoints directos requeridos por Tareas 3.2 y 3.3 ─────────────────
  // Tarea 3.2: /generate-qr (GET)
  app.get('/generate-qr',        jwtVerify, qrRateLimiter, qrController.generateQr);
  app.get('/api/v1/generate-qr', jwtVerify, qrRateLimiter, qrController.generateQr);

  // /create-ticket (POST) -> SOLO staff/admin + rate limit anti-emisión masiva.
  // ORDEN CRÍTICO: staffOnlyVerify ANTES del limitador para que este keye por
  // req.user.id (por-usuario) y no por IP. Ver nota en ticketRoutes.js.
  app.post('/create-ticket',        staffOnlyVerify, ticketCreateRateLimiter, ticketController.createTicket);
  app.post('/api/v1/create-ticket', staffOnlyVerify, ticketCreateRateLimiter, ticketController.createTicket);

  // Tarea 3.3: /validate-ticket (POST) -> Protegido por API Key del torniquete + Rate Limiter
  app.post('/validate-ticket',        validateRateLimiter, requireTurnstileApiKey, ticketController.validateTicket);
  app.post('/api/v1/validate-ticket', validateRateLimiter, requireTurnstileApiKey, ticketController.validateTicket);

  // ── 2. Rutas modulares agrupadas /api/v1/... ──────────────────────────────
  app.use('/api/v1/qr',      qrRateLimiter,       qrRoutes);
  app.use('/api/v1/tickets', createTicketRoutes({ redisClient }));
  // Rutas internas (payment-service → access-service). Montadas ANTES de
  // /api/v1/access para no heredar el rate limiter del torniquete ni la API Key.
  app.use('/api/v1/access/internal', internalRoutes);
  app.use('/api/v1/access',  validateRateLimiter, accessRoutes);
  app.use('/api/v1/adms',    zkAdmsRoutes);
  app.use('/iclock',         zkAdmsRoutes);


  security.applyFinal(app);

  const PORT   = parseInt(process.env.PORT || '3002', 10);
  const server = app.listen(PORT, '0.0.0.0', () =>
    security.logger.info(`access-service escuchando en :${PORT}`, {
      redisEnabled: !!redisClient,
      qrTtl:        process.env.QR_TTL_SECONDS || 30,
    })
  );

  const shutdown = async (sig) => {
    security.logger.info(`${sig} recibido. Cerrando access-service...`);
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
  console.error('[access-service] Error fatal en arranque:', err.message);
  process.exit(1);
});
