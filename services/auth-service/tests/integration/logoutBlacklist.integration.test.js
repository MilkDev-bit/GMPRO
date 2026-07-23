/**
 * @file services/auth-service/tests/integration/logoutBlacklist.integration.test.js
 * @description INTEGRACIÓN contra REDIS real: revocación de access token en logout.
 *
 * Flujo E2E:
 *   1. Se firma un access token válido.
 *   2. La ruta protegida lo ACEPTA (200).
 *   3. Se ejecuta el HANDLER REAL de logout (authController.logout) → escribe
 *      jwt:blacklist:<jti> en el Redis efímero vía tokenService.revokeAccessToken.
 *   4. El MISMO token, en la ruta protegida, ahora es RECHAZADO (401) porque
 *      jwtVerify consulta la blacklist en Redis.
 *
 * Se salta si no hay REDIS_URL (suite unitaria normal). Solo se mockea lo que no
 * participa en la revocación (identidad/email/refresh-model); tokenService y
 * jwtVerify son REALES y hablan con el Redis real.
 */

'use strict';

process.env.NODE_ENV                = 'test';
process.env.PORT                    = '3001';
process.env.SUPABASE_URL            = 'https://fake.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_' + 'x'.repeat(40);
process.env.SUPABASE_DB_SCHEMA      = 'public';
process.env.JWT_SECRET              = 'test-jwt-secret-'.padEnd(64, 'k');
process.env.JWT_EXPIRES_IN          = '15m';
process.env.JWT_REFRESH_EXPIRES_IN  = '30d';
process.env.JWT_ALGORITHM           = 'HS512';
process.env.BCRYPT_ROUNDS           = '10';
process.env.ENCRYPTION_KEY          = 'a'.repeat(64);
process.env.CORS_ALLOWED_ORIGINS    = 'https://app.gympro.com';

const HAS_REDIS = !!process.env.REDIS_URL;

// Mockear SOLO lo que no participa en la revocación (evita tocar Supabase/Resend).
jest.mock('../../src/models/refreshTokenModel', () => ({
  findByHash: async () => null, revokeFamily: async () => 0, revokeAllForUser: async () => 0,
}));
jest.mock('../../src/models/userModel', () => ({}));
jest.mock('../../src/services/emailService', () => ({}));

const express      = require('express');
const cookieParser = require('cookie-parser');
const request      = require('supertest');
const jwt          = require('jsonwebtoken');
const crypto       = require('crypto');
const Redis        = require('ioredis');

const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');
const authController = require('../../src/controllers/authController');

function signToken(userId, jti) {
  return jwt.sign(
    { sub: userId, role: 'miembro', jti, email: `${userId}@x.com` },
    process.env.JWT_SECRET, { algorithm: process.env.JWT_ALGORITHM, expiresIn: '15m' });
}

(HAS_REDIS ? describe : describe.skip)('INTEGRACIÓN — revocación de access token en logout (Redis real)', () => {
  let redis, app;

  function buildApp() {
    const a = express();
    a.use(express.json());
    a.use(cookieParser());
    a.use((req, _res, next) => { req.redisClient = redis; next(); }); // como main.js
    const jwtVerify = createJwtVerifyMiddleware({ redisClient: redis });
    a.post('/logout',    jwtVerify, authController.logout);
    a.get('/protected',  jwtVerify, (req, res) => res.json({ success: true, data: { userId: req.user.id }, error: null }));
    return a;
  }

  beforeAll(() => { redis = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: 2 }); });
  afterAll(async () => { await redis.quit(); });
  beforeEach(async () => { await redis.flushdb(); app = buildApp(); });

  test('logout escribe la blacklist en Redis y el mismo token pasa a 401', async () => {
    const jti   = crypto.randomUUID();
    const token = signToken('user-A', jti);
    const bearer = { Authorization: `Bearer ${token}` };

    // 1. Antes del logout: ruta protegida ACEPTA.
    const before = await request(app).get('/protected').set(bearer);
    expect(before.status).toBe(200);

    // 2. Logout REAL → escribe jwt:blacklist:<jti> en Redis.
    const out = await request(app).post('/logout').set(bearer);
    expect(out.status).toBe(200);

    // 3. Verificación DIRECTA en Redis: la clave existe.
    expect(await redis.get(`jwt:blacklist:${jti}`)).toBe('1');

    // 4. El MISMO token en la ruta protegida → 401 (revocado).
    const after = await request(app).get('/protected').set(bearer);
    expect(after.status).toBe(401);
  });

  test('un token NO revocado sigue siendo válido (control)', async () => {
    const token = signToken('user-B', crypto.randomUUID());
    const res = await request(app).get('/protected').set({ Authorization: `Bearer ${token}` });
    expect(res.status).toBe(200);
  });
});
