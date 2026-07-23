/**
 * @file services/access-service/tests/ticketFlow.test.js
 * @description Prueba de integración (Jest + supertest) del flujo de tickets:
 *              RBAC (403/éxito), validación por torniquete y rate limiting (429).
 *
 * QUÉ SE INTEGRA DE VERDAD (runtime, no estático):
 *   · Express + el router REAL (factory `createTicketRoutes`).
 *   · Verificación REAL de JWT (`createJwtVerifyMiddleware`) con firma HS512.
 *   · RBAC REAL leído de la config externalizada (`env.STAFF_ROLES`).
 *   · Rate limiter REAL (`createUserRateLimiter`, store en memoria en el test).
 *   · Auth de torniquete REAL (`requireTurnstileApiKey`, timing-safe).
 *
 * QUÉ SE MOCKEA Y POR QUÉ:
 *   Solo la capa de datos (`accessModel`). Todos los controles de seguridad
 *   (401/403/429/API-key) se ejecutan ANTES de tocar la BD, así que mockear el
 *   modelo NO debilita ninguna aserción de seguridad: aísla el test de Supabase.
 */

'use strict';

// ── 1. Entorno ANTES de requerir nada (environment.js lee env al cargar) ─────
process.env.NODE_ENV                     = 'test';
process.env.PORT                         = '3002'; // validador exige +v > 0
process.env.SUPABASE_URL                 = 'https://fake.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY    = 'sb_secret_' + 'x'.repeat(40);
process.env.SUPABASE_DB_SCHEMA           = 'access_service_db';
process.env.JWT_SECRET                   = 'test-jwt-secret-'.padEnd(64, 'k'); // ≥64
process.env.JWT_ALGORITHM                = 'HS512';
process.env.TURNSTILE_API_KEY            = 'turnstile-test-key-'.padEnd(40, '0'); // ≥32
process.env.PAYMENT_SERVICE_INTERNAL_URL = 'http://payment.internal:3003';
process.env.INTER_SERVICE_SECRET         = 'inter-service-secret-'.padEnd(32, 'z');
process.env.CORS_ALLOWED_ORIGINS         = 'https://app.gympro.com';
// AES-256: 64 hex exactos (32 bytes). Obligatorio aunque este test no cifre QR.
process.env.AES_ENCRYPTION_KEY           = 'a'.repeat(64);
// Límite bajo para que la ráfaga dispare 429 rápido y determinista.
process.env.RATE_LIMIT_TICKET_MAX        = '3';
// STAFF_ROLES por defecto (staff,admin) — no se define para probar el fallback.

// ── 2. Mock de la capa de datos (solo el modelo) ─────────────────────────────
jest.mock('../src/models/accessModel', () => ({
  createTicketRecord: jest.fn(async (data) => ({
    id:            'ticket-uuid-1',
    codigo_ticket: 'GP-AB12-CD34-EF56',
    estado:        'active',
    usuario_id:    data.usuario_id,
    creado_at:     new Date().toISOString(),
    expira_en:     data.expira_en,
    usado_at:      null,
    notas:         data.notas,
  })),
  consumeTicketAtomically: jest.fn(async () => ({
    success: true,
    ticket:  { usuario_id: null, codigo_ticket: 'GP-AB12-CD34-EF56' },
  })),
  recordAccess: jest.fn(async () => ({ id: 'hist-1' })),
}));

const express  = require('express');
const request  = require('supertest');
const jwt      = require('jsonwebtoken');
const crypto   = require('crypto');

const createTicketRoutes = require('../src/routes/ticketRoutes');
const env                = require('../src/config/environment');

// ── 3. Redis real si CI lo provee; si no, MemoryStore (dev local) ────────────
// El objetivo en CI es validar el rate limiter con el RedisStore REAL (estado
// compartido entre réplicas), no el MemoryStore por-proceso. Si REDIS_URL está
// definida (contenedor efímero del workflow), se usa Redis; en local, null.
let redisClient = null;
if (process.env.REDIS_URL) {
  const Redis = require('ioredis');
  redisClient = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: 2 });
}

// ── 4. App de prueba: monta el router REAL (mismo que producción) ────────────
function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/v1/tickets', createTicketRoutes({ redisClient }));
  return app;
}

// ── 4. Helper: firma un JWT válido con el rol indicado ───────────────────────
function signToken(role, sub = `user-${role}-1`) {
  return jwt.sign(
    { sub, role, jti: crypto.randomUUID(), email: `${sub}@gympro.com` },
    process.env.JWT_SECRET,
    { algorithm: process.env.JWT_ALGORITHM, expiresIn: '5m' },
  );
}

const auth = (token) => ({ Authorization: `Bearer ${token}` });

describe('Flujo de tickets — RBAC, torniquete y rate limiting', () => {
  let app;
  // Con Redis real el estado persiste entre reconstrucciones de la app, así que
  // se limpia antes de cada test para contar de forma determinista. Con
  // MemoryStore (local) cada instancia arranca limpia; el flush es no-op guardado.
  beforeEach(async () => {
    if (redisClient) await redisClient.flushdb();
    app = buildApp();
  });

  afterAll(async () => {
    if (redisClient) await redisClient.quit();
  });

  // ── RBAC: rechazo ──────────────────────────────────────────────────────────
  test('miembro → POST /create-ticket → 403 (RBAC)', async () => {
    const res = await request(app)
      .post('/api/v1/tickets/create')
      .set(auth(signToken('miembro')))
      .send({ vigencia_horas: 24 });

    expect(res.status).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('sin JWT → 401', async () => {
    const res = await request(app).post('/api/v1/tickets/create').send({});
    expect(res.status).toBe(401);
  });

  // ── RBAC: éxito ────────────────────────────────────────────────────────────
  test('staff → POST /create-ticket → 201 (emite pase)', async () => {
    const res = await request(app)
      .post('/api/v1/tickets/create')
      .set(auth(signToken('staff')))
      .send({ vigencia_horas: 24, notas: 'Pase de prueba' });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.codigo_ticket).toMatch(/^GP-/);
  });

  test('admin también puede emitir (rol alternativo autorizado)', async () => {
    const res = await request(app)
      .post('/api/v1/tickets/create')
      .set(auth(signToken('admin')))
      .send({ vigencia_horas: 12 });
    expect(res.status).toBe(201);
  });

  // ── Validación por torniquete ──────────────────────────────────────────────
  test('torniquete valida el ticket con x-turnstile-key → 200', async () => {
    const res = await request(app)
      .post('/api/v1/tickets/validate')
      .set('x-turnstile-key', process.env.TURNSTILE_API_KEY)
      .send({ codigo_ticket: 'GP-AB12-CD34-EF56' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('validate SIN API key de torniquete → 401', async () => {
    const res = await request(app)
      .post('/api/v1/tickets/validate')
      .send({ codigo_ticket: 'GP-AB12-CD34-EF56' });
    expect(res.status).toBe(401);
  });

  // ── Rate limiting ──────────────────────────────────────────────────────────
  test('ráfaga de staff supera el límite (3/min) → 429', async () => {
    const token = signToken('staff'); // mismo usuario → mismo contador
    const codes = [];
    for (let i = 0; i < 5; i++) {
      // eslint-disable-next-line no-await-in-loop
      const res = await request(app)
        .post('/api/v1/tickets/create')
        .set(auth(token))
        .send({ vigencia_horas: 1 });
      codes.push(res.status);
    }
    // Con RATE_LIMIT_TICKET_MAX=3: las 3 primeras 201, las siguientes 429.
    expect(codes.filter((c) => c === 201).length).toBe(env.RATE_LIMIT_TICKET_MAX);
    expect(codes).toContain(429);
  });

  // ── Prueba del KEYING POR USUARIO (regresión del bug de orden de middlewares) ─
  // Este es el test que valida el fix: el limitador ahora corre DESPUÉS de la
  // verificación JWT, así que keya por req.user.id. Un usuario A que agota su
  // cuota NO debe afectar a un usuario B que comparte la MISMA IP (supertest usa
  // 127.0.0.1 para ambos). Si el keying fuera por IP —el bug anterior— B recibiría
  // 429 de inmediato; con keying por usuario, B emite con éxito.
  test('keying por usuario: A agota cuota, B (misma IP, otro user) sigue emitiendo', async () => {
    const tokenA = signToken('staff', 'staff-user-A');
    const tokenB = signToken('staff', 'staff-user-B');

    // A dispara 5 → agota su bucket (3×201, luego 429).
    const codesA = [];
    for (let i = 0; i < 5; i++) {
      // eslint-disable-next-line no-await-in-loop
      const r = await request(app)
        .post('/api/v1/tickets/create')
        .set(auth(tokenA))
        .send({ vigencia_horas: 1 });
      codesA.push(r.status);
    }
    expect(codesA).toContain(429); // A quedó limitado

    // B, misma IP, bucket independiente → debe poder emitir (201), no 429.
    const resB = await request(app)
      .post('/api/v1/tickets/create')
      .set(auth(tokenB))
      .send({ vigencia_horas: 1 });

    expect(resB.status).toBe(201); // ← falla si el keying fuese por IP
  });
});
