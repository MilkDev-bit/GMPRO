/**
 * @file services/auth-service/tests/sessionManagement.test.js
 * @description Gestión de sesiones/dispositivos: listar, cerrar una, cerrar
 *              todas, y sobre todo la protección BOLA/IDOR (no cerrar sesiones
 *              ajenas). Se mockea la capa de datos con un store con OWNER.
 */

'use strict';

// ── Entorno ANTES de requerir nada ───────────────────────────────────────────
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

// ── Store mock con OWNER (para probar el candado BOLA de verdad) ─────────────
jest.mock('../src/models/refreshTokenModel', () => {
  const owners = new Map(); // familyId -> ownerUserId
  return {
    __setFamily: (familyId, ownerId) => owners.set(familyId, ownerId),
    __reset: () => owners.clear(),
    listActiveSessionsForUser: jest.fn(async (userId) =>
      [...owners.entries()]
        .filter(([, owner]) => owner === userId)
        .map(([familyId]) => ({ familyId, device: 'Test UA', ip: '1.2.3.4',
          started: '2026-07-20T00:00:00Z', lastActive: '2026-07-23T00:00:00Z',
          expiresAt: '2026-08-22T00:00:00Z' }))
    ),
    // Candado de propiedad: solo revoca si la familia pertenece al userId.
    revokeFamilyForUser: jest.fn(async (userId, familyId) =>
      owners.get(familyId) === userId ? 1 : 0
    ),
    revokeAllForUser: jest.fn(async (userId) =>
      [...owners.values()].filter((o) => o === userId).length
    ),
  };
});

const express = require('express');
const request = require('supertest');
const jwt     = require('jsonwebtoken');
const crypto  = require('crypto');

const { createJwtVerifyMiddleware } = require('../../../packages_shared/security/jwtVerify');
const sessionController  = require('../src/controllers/sessionController');
const refreshTokenModel  = require('../src/models/refreshTokenModel');

function buildApp() {
  const app = express();
  app.use(express.json());
  const jwtVerify = createJwtVerifyMiddleware();
  app.get('/sessions',              jwtVerify, sessionController.listSessions);
  app.delete('/sessions',           jwtVerify, sessionController.revokeAllSessions);
  app.delete('/sessions/:familyId', jwtVerify, sessionController.revokeSession);
  return app;
}

function signToken(userId) {
  return jwt.sign(
    { sub: userId, role: 'miembro', jti: crypto.randomUUID(), email: `${userId}@x.com` },
    process.env.JWT_SECRET,
    { algorithm: process.env.JWT_ALGORITHM, expiresIn: '5m' },
  );
}
const auth = (uid) => ({ Authorization: `Bearer ${signToken(uid)}` });

describe('Gestión de sesiones / dispositivos', () => {
  let app;
  const FAM_A = '11111111-1111-1111-1111-111111111111'; // de userA
  const FAM_B = '22222222-2222-2222-2222-222222222222'; // de userB

  beforeEach(() => {
    refreshTokenModel.__reset();
    refreshTokenModel.__setFamily(FAM_A, 'userA');
    refreshTokenModel.__setFamily(FAM_B, 'userB');
    jest.clearAllMocks();
    app = buildApp();
  });

  test('sin JWT → 401', async () => {
    expect((await request(app).get('/sessions')).status).toBe(401);
  });

  test('GET /sessions lista solo las del usuario autenticado', async () => {
    const res = await request(app).get('/sessions').set(auth('userA'));
    expect(res.status).toBe(200);
    expect(res.body.data.total).toBe(1);
    expect(res.body.data.sessions[0].familyId).toBe(FAM_A);
    expect(refreshTokenModel.listActiveSessionsForUser).toHaveBeenCalledWith('userA');
  });

  test('DELETE /sessions/:familyId propio → 200', async () => {
    const res = await request(app).delete(`/sessions/${FAM_A}`).set(auth('userA'));
    expect(res.status).toBe(200);
    expect(res.body.data.revoked).toBe(1);
    expect(refreshTokenModel.revokeFamilyForUser).toHaveBeenCalledWith('userA', FAM_A);
  });

  // ── BOLA / IDOR: userB NO puede cerrar la sesión de userA ───────────────────
  test('BOLA: userB intenta cerrar la familia de userA → 404 (no la toca)', async () => {
    const res = await request(app).delete(`/sessions/${FAM_A}`).set(auth('userB'));
    expect(res.status).toBe(404);
    // El modelo se llamó con el id de userB (el candado), no con el dueño real.
    expect(refreshTokenModel.revokeFamilyForUser).toHaveBeenCalledWith('userB', FAM_A);
  });

  test('DELETE /sessions cierra todas las del usuario → 200', async () => {
    const res = await request(app).delete('/sessions').set(auth('userA'));
    expect(res.status).toBe(200);
    expect(res.body.data.revoked).toBe(1);
    expect(refreshTokenModel.revokeAllForUser).toHaveBeenCalledWith('userA');
  });
});
