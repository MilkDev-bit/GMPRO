/**
 * @file services/auth-service/tests/rateLimiterFailClosed.test.js
 * @description A10-1 — el rate limiter es FAIL-CLOSED: un fallo de Redis bloquea
 * el endpoint afectado de forma segura SIN tumbar el servicio completo, y sin
 * caer silenciosamente a MemoryStore en producción.
 */

'use strict';

const express = require('express');
const request = require('supertest');
const {
  createIpRateLimiter,
} = require('../../../packages_shared/security/rateLimiter');

function buildApp(mw) {
  const app = express();
  app.use(express.json());
  // /health NO pasa por el limiter en el orden real, pero lo declaramos antes
  // para comprobar que el servicio sigue "vivo" aunque el limiter falle.
  app.get('/health', (_req, res) => res.json({ success: true }));
  app.use(mw);
  app.get('/x', (_req, res) => res.json({ success: true }));
  // Error handler: captura el fail-closed por error de store (passOnStoreError:false).
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => res.status(500).json({ success: false, error: 'store' }));
  return app;
}

describe('A10-1 · Rate limiter fail-closed', () => {
  const OLD_ENV = process.env.NODE_ENV;
  afterEach(() => { process.env.NODE_ENV = OLD_ENV; });

  test('PRODUCCIÓN sin Redis → endpoint 503 (fail-closed), /health sigue 200 (servicio vivo)', async () => {
    process.env.NODE_ENV = 'production';
    const app = buildApp(createIpRateLimiter({ redisClient: null, prefix: 'rl:test:prod:' }));

    const res = await request(app).get('/x');
    expect(res.status).toBe(503);           // NO se cae a MemoryStore; se cierra el endpoint
    expect(res.body.error).toMatch(/no disponible/i);

    const health = await request(app).get('/health');
    expect(health.status).toBe(200);        // el servicio NO se cae en cascada
  });

  test('/health y /ready quedan exentos del fail-closed en producción', async () => {
    process.env.NODE_ENV = 'production';
    const mw = createIpRateLimiter({ redisClient: null, prefix: 'rl:test:health:' });
    const app = express();
    app.use(mw);
    app.get('/ready', (_req, res) => res.json({ ok: true }));
    const res = await request(app).get('/ready');
    expect(res.status).toBe(200);
  });

  test('DESARROLLO sin Redis → MemoryStore permite hasta el límite y luego 429', async () => {
    process.env.NODE_ENV = 'development';
    const app = buildApp(createIpRateLimiter({ redisClient: null, max: 2, windowMs: 60_000, prefix: 'rl:test:dev:' }));

    expect((await request(app).get('/x')).status).toBe(200);
    expect((await request(app).get('/x')).status).toBe(200);
    expect((await request(app).get('/x')).status).toBe(429);   // límite aplicado
  });

  test('Error de store en RUNTIME con passOnStoreError:false → request bloqueada (no 200), sin crash', async () => {
    // Verifica el contrato en el que se apoya A10-1: si el store falla al contar
    // (Redis caído en runtime), la request NO evade el límite. Se usa un store
    // mock que rechaza en increment() — evita el flakiness de rate-limit-redis,
    // que carga su script Lua en el constructor (no en request).
    const { rateLimit } = require('express-rate-limit');
    const brokenStore = {
      init() {},
      async increment() { throw new Error('Redis down (runtime)'); },
      async decrement() {},
      async resetKey() {},
    };

    const app = express();
    app.use(rateLimit({ windowMs: 60_000, max: 5, passOnStoreError: false, store: brokenStore }));
    app.get('/x', (_req, res) => res.json({ success: true }));
    // eslint-disable-next-line no-unused-vars
    app.use((err, _req, res, _next) => res.status(500).json({ success: false, error: 'store' }));

    const res = await request(app).get('/x');
    expect(res.status).not.toBe(200);   // fail-closed: no se deja pasar
    // El proceso sigue vivo: una segunda request tampoco crashea el servicio.
    const res2 = await request(app).get('/x');
    expect(res2.status).not.toBe(200);
  });
});
