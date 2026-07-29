/**
 * @file services/auth-service/src/main.js
 * @description Entry point del auth-service.
 *
 * Demuestra el uso correcto del módulo de seguridad compartido y el orden
 * preciso de inicialización para una aplicación Express segura en producción.
 *
 * Secuencia de arranque:
 *   1. Validar variables de entorno críticas (falla rápido)
 *   2. Conectar a Redis (opcional pero recomendado)
 *   3. Aplicar middlewares de seguridad globales
 *   4. Montar rutas
 *   5. Aplicar middlewares finales (404 + error handler)
 *   6. Escuchar en puerto
 *   7. Configurar graceful shutdown
 */

'use strict';

const express = require('express');
const { createSecurityMiddleware } = require('../../../packages_shared/security');
const { createAuthRateLimiter, createUserRateLimiter, createIpRateLimiter, createAccountRateLimiter } = require('../../../packages_shared/security/rateLimiter');

// ─── Validación de entorno (fail-fast) ────────────────────────────────────────
// Si faltan variables críticas, el proceso debe fallar inmediatamente
// antes de servir cualquier request. Railway lo detectará como unhealthy.
const REQUIRED_ENV = [
  'NODE_ENV', 'PORT', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY',
  'BCRYPT_ROUNDS',
];

const missingEnv = REQUIRED_ENV.filter((key) => !process.env[key]);
if (missingEnv.length > 0) {
  console.error(`[auth-service] Variables de entorno faltantes: ${missingEnv.join(', ')}`);
  process.exit(1);
}

// ─── Imports de módulos del servicio ─────────────────────────────────────────
const createAuthRoutes = require('./routes/authRoutes'); // factory({ redisClient })
const createPasswordRoutes = require('./routes/passwordRoutes'); // factory({ redisClient })
const createAdminRoutes = require('./routes/adminRoutes'); // factory({ redisClient })

// ─── Inicialización de la aplicación ─────────────────────────────────────────
async function bootstrap() {
  const app = express();

  // Confiar en el proxy de Railway (necesario para getRealIp con X-Forwarded-For)
  // '1' = confiar en el primer proxy. Aumentar si hay múltiples proxies en cadena.
  app.set('trust proxy', 1);

  // ─── Conectar a Redis ──────────────────────────────────────────────────────
  let redisClient = null;
  if (process.env.REDIS_URL) {
    const Redis = require('ioredis');
    redisClient = new Redis(process.env.REDIS_URL, {
      // Reconexión automática con backoff exponencial
      retryStrategy: (times) => Math.min(times * 100, 3000),
      lazyConnect: false,
      enableReadyCheck: true,
      maxRetriesPerRequest: 3,
    });

    redisClient.on('connect', () =>
      security.logger.info('Redis conectado correctamente'));
    redisClient.on('error', (err) =>
      security.logger.error('Error de conexión Redis', { error: err.message }));
  }

  // ─── Crear e inicializar el módulo de seguridad ───────────────────────────
  const security = createSecurityMiddleware({
    serviceName: 'auth-service',
    redisClient,
    maxPayloadSize: '50kb',  // Auth puede tener payloads un poco mayores (historial clínico)
    globalRateMax: 100,
    isApiOnly: true,
  });

  // 1. Aplicar middlewares globales (Helmet, CORS, Rate Limit, Body Parser, Sanitización)
  security.applyGlobal(app);

  // ─── Exponer Redis a controllers y rutas ──────────────────────────────────
  // req.redisClient → usado por authController.logout para escribir la BLACKLIST
  //   de access tokens (revocación en logout). Antes NO se inyectaba, así que la
  //   revocación era código muerto: el token seguía válido tras el logout.
  // app.set('redisClient') → usado por passkeyController (retos WebAuthn).
  app.set('redisClient', redisClient);
  app.use((req, _res, next) => { req.redisClient = redisClient; next(); });

  // ─── Endpoint de salud (Railway healthcheck) ──────────────────────────────
  // Sin autenticación. Sin rate limiting (excluido en la config).
  // Solo verifica que el proceso responde — no verifica DB (evitar timeouts en healthcheck).
  app.get('/health', (_req, res) => {
    res.status(200).json({
      success: true,
      data: {
        service: 'auth-service',
        status: 'healthy',
        uptime: Math.floor(process.uptime()),
        timestamp: new Date().toISOString(),
      },
      error: null,
    });
  });

  // ─── Rate limiters específicos por ruta ───────────────────────────────────
  // Aplicar ANTES de montar las rutas que deben ser limitadas
  const authRateLimiter = createAuthRateLimiter({
    redisClient,
    max: parseInt(process.env.RATE_LIMIT_LOGIN_MAX || '5', 10),
    windowMs: parseInt(process.env.RATE_LIMIT_LOGIN_WINDOW_MINUTES || '15', 10) * 60_000,
    prefix: 'rl:auth:login:',
  });

  const userRateLimiter = createUserRateLimiter({
    redisClient,
    max: 200,
    windowMs: 60_000,
    prefix: 'rl:auth:user:',
  });

  // ─── Limiter dedicado para /register (cuenta TODAS las requests) ───────────
  // authRateLimiter usa skipSuccessfulRequests:true (correcto para login: no
  // penaliza al que acierta la contraseña). Pero para /register eso deja el
  // control APAGADO justo para el abuso a frenar: un registro EXITOSO (201) no
  // cuenta, así que un atacante crea cuentas en masa con emails únicos →
  // contaminación de BD + email-bombing (cada alta dispara correo de verificación).
  // createIpRateLimiter NO omite las exitosas: cuenta todo. Umbral generoso para
  // no romper altas legítimas desde una wifi compartida (NAT del gimnasio).
  const registerRateLimiter = createIpRateLimiter({
    redisClient,
    max:      parseInt(process.env.RATE_LIMIT_REGISTER_MAX || '10', 10),
    windowMs: parseInt(process.env.RATE_LIMIT_REGISTER_WINDOW_MINUTES || '60', 10) * 60_000,
    prefix:   'rl:auth:register:',
  });

  // ─── Limiter POR CUENTA para /login (anti-fuerza-bruta distribuida) ────────
  // authRateLimiter limita por IP; no detiene a un atacante que rota IPs contra
  // UNA cuenta. Este limiter agrupa por email (10 fallos/hora por cuenta,
  // independiente de la IP) y solo cuenta fallos, así el dueño legítimo no se
  // bloquea al teclear bien. Defensa en profundidad: /login recibe ambos.
  const loginAccountRateLimiter = createAccountRateLimiter({
    redisClient,
    max:      parseInt(process.env.RATE_LIMIT_LOGIN_ACCOUNT_MAX || '10', 10),
    windowMs: parseInt(process.env.RATE_LIMIT_LOGIN_ACCOUNT_WINDOW_MINUTES || '60', 10) * 60_000,
    prefix:   'rl:auth:account:',
    field:    'email',
  });

  // ─── Montar rutas ─────────────────────────────────────────────────────────
  // Los limiters de path específico se montan ANTES del grupo; Express evalúa
  // los app.use en orden y el path más específico corre primero.
  app.use('/api/v1/auth/register', registerRateLimiter);
  app.use('/api/v1/auth/login',    loginAccountRateLimiter);

  // Rutas públicas (sin JWT): rate limit anti-fuerza-bruta por IP (authRateLimiter)
  app.use('/api/v1/auth', authRateLimiter, createAuthRoutes({ redisClient }));

  // Rutas protegidas (con JWT): rate limit por usuario
  app.use('/api/v1/auth/password', userRateLimiter, createPasswordRoutes({ redisClient }));

  // Panel de administración (staff/admin): gestión de miembros.
  app.use('/api/v1/auth/admin', userRateLimiter, createAdminRoutes({ redisClient }));

  // 2. Aplicar middlewares finales (404 + error handler) — SIEMPRE AL FINAL
  security.applyFinal(app);

  // ─── Iniciar servidor ─────────────────────────────────────────────────────
  const PORT = parseInt(process.env.PORT || '3001', 10);
  const server = app.listen(PORT, '0.0.0.0', () => {
    security.logger.info(`auth-service escuchando en puerto ${PORT}`, {
      nodeVersion: process.version,
      environment: process.env.NODE_ENV,
      redisEnabled: !!redisClient,
    });
  });

  // ─── Graceful Shutdown ────────────────────────────────────────────────────
  // Railway envía SIGTERM antes de detener el contenedor.
  // dumb-init lo propaga al proceso Node.js.
  // Cerramos las conexiones activas antes de salir para no perder requests en vuelo.
  const gracefulShutdown = async (signal) => {
    security.logger.info(`Señal ${signal} recibida. Iniciando graceful shutdown...`);

    // 1. Dejar de aceptar nuevas conexiones
    server.close(async () => {
      security.logger.info('Servidor HTTP cerrado. Cerrando conexiones restantes...');

      // 2. Cerrar Redis si está conectado
      if (redisClient) {
        await redisClient.quit();
        security.logger.info('Conexión Redis cerrada.');
      }

      security.logger.info('Graceful shutdown completado. Proceso terminado.');
      process.exit(0);
    });

    // Timeout de seguridad: si el shutdown tarda más de 10s, forzar salida
    setTimeout(() => {
      security.logger.error('Graceful shutdown timeout. Forzando salida.');
      process.exit(1);
    }, 10_000);
  };

  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT',  () => gracefulShutdown('SIGINT'));

  return server;
}

// Iniciar la aplicación
bootstrap().catch((err) => {
  console.error('[auth-service] Error fatal durante el arranque:', err.message);
  process.exit(1);
});
