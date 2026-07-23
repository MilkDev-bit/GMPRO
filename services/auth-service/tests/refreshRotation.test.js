/**
 * @file services/auth-service/tests/refreshRotation.test.js
 * @description Prueba de integración del flujo de refresh token con FAMILIAS:
 *              rotación, expiración server-side y REUSE/REPLAY DETECTION.
 *
 * Se mockea SOLO la capa de datos: refreshTokenModel se sustituye por un fake
 * STATEFUL (un Map en memoria) que replica fielmente la semántica real
 * (issue / findByHash / consumeAtomically / revokeFamily). Así el test ejercita
 * la LÓGICA DE DECISIÓN real del controller contra un store creíble, sin BD.
 */

'use strict';

// ── Entorno ANTES de requerir nada (environment.js valida al cargar) ─────────
process.env.NODE_ENV                = 'test';
process.env.PORT                    = '3001';
process.env.SUPABASE_URL            = 'https://fake.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_' + 'x'.repeat(40);
process.env.SUPABASE_DB_SCHEMA      = 'auth_service_db';
process.env.JWT_SECRET              = 'test-jwt-secret-'.padEnd(64, 'k');
process.env.JWT_EXPIRES_IN          = '15m';
process.env.JWT_REFRESH_EXPIRES_IN  = '30d';
process.env.JWT_ALGORITHM           = 'HS512';
process.env.BCRYPT_ROUNDS           = '10';
process.env.ENCRYPTION_KEY          = 'a'.repeat(64);
process.env.CORS_ALLOWED_ORIGINS    = 'https://app.gympro.com';
process.env.REFRESH_TOKEN_TTL_DAYS  = '30';

// ── Fake stateful de la capa de datos de refresh tokens ──────────────────────
jest.mock('../src/models/refreshTokenModel', () => {
  const rows = new Map(); // id -> row
  let seq = 0;
  return {
    __rows: rows,
    __reset: () => { rows.clear(); seq = 0; },
    issue: jest.fn(async ({ userId, tokenHash, familyId, expiresAt }) => {
      const id = 't' + (++seq);
      rows.set(id, {
        id, user_id: userId, family_id: familyId, token_hash: tokenHash,
        is_consumed: false, expires_at: expiresAt, revoked_at: null, consumed_at: null,
      });
      return { id, family_id: familyId, expires_at: expiresAt };
    }),
    findByHash: jest.fn(async (h) => {
      for (const r of rows.values()) if (r.token_hash === h) return { ...r };
      return null;
    }),
    consumeAtomically: jest.fn(async (id) => {
      const r = rows.get(id);
      if (r && !r.is_consumed && !r.revoked_at) {
        r.is_consumed = true; r.consumed_at = new Date().toISOString(); return true;
      }
      return false;
    }),
    revokeFamily: jest.fn(async (familyId) => {
      let n = 0;
      for (const r of rows.values()) if (r.family_id === familyId && !r.revoked_at) { r.revoked_at = new Date().toISOString(); n++; }
      return n;
    }),
    revokeAllForUser: jest.fn(async (userId) => {
      let n = 0;
      for (const r of rows.values()) if (r.user_id === userId && !r.revoked_at) { r.revoked_at = new Date().toISOString(); n++; }
      return n;
    }),
  };
});

// userModel: solo findById (usado por refresh) y recordSuccessfulLogin.
jest.mock('../src/models/userModel', () => ({
  findById: jest.fn(async (id) => ({ id, email: 'user@x.com', rol: 'miembro', activo: true })),
  recordSuccessfulLogin: jest.fn(async () => {}),
}));

// emailService no se usa en este flujo; se neutraliza para evitar side-effects.
jest.mock('../src/services/emailService', () => ({}));

const express     = require('express');
const cookieParser = require('cookie-parser');
const request     = require('supertest');
const crypto      = require('crypto');

const authController   = require('../src/controllers/authController');
const refreshTokenModel = require('../src/models/refreshTokenModel');
const tokenService     = require('../src/services/tokenService');

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use(cookieParser());
  app.post('/refresh', authController.refreshToken);
  return app;
}

const cookie = (token) => ['refreshToken=' + token];

/** Siembra una sesión (una familia) y devuelve el refresh token en texto plano. */
async function seedSession({ userId = 'u1', ttlMs = 30 * 24 * 60 * 60_000 } = {}) {
  const token = crypto.randomBytes(64).toString('base64url');
  const hash  = crypto.createHash('sha256').update(token).digest('hex');
  const familyId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + ttlMs).toISOString();
  await refreshTokenModel.issue({ userId, tokenHash: hash, familyId, expiresAt });
  return { token, familyId };
}

describe('Refresh token — rotación, expiración y reuse detection', () => {
  let app;
  beforeEach(() => { refreshTokenModel.__reset(); jest.clearAllMocks(); app = buildApp(); });

  test('sin cookie → 401', async () => {
    const res = await request(app).post('/refresh').send();
    expect(res.status).toBe(401);
  });

  test('refresh válido → 200, rota (consume + emite en la misma familia)', async () => {
    const { token, familyId } = await seedSession();
    const res = await request(app).post('/refresh').set('Cookie', cookie(token)).send();

    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeTruthy();
    expect(res.body.data.refreshToken).toBeTruthy();
    expect(res.body.data.refreshToken).not.toBe(token);          // token rotado
    expect(refreshTokenModel.consumeAtomically).toHaveBeenCalledTimes(1); // solo el refresh consume
    // La rotación emite el nuevo token en la MISMA familia (2ª llamada a issue;
    // la 1ª fue la siembra de la sesión).
    const lastIssue = refreshTokenModel.issue.mock.calls.at(-1)[0];
    expect(lastIssue.familyId).toBe(familyId);
  });

  test('REUSE de un token ya consumido → 401 y revoca la familia', async () => {
    const { token, familyId } = await seedSession();

    // 1er uso: legítimo, rota correctamente.
    const ok = await request(app).post('/refresh').set('Cookie', cookie(token)).send();
    expect(ok.status).toBe(200);
    const rotated = ok.body.data.refreshToken;

    // 2º uso del MISMO token viejo (ya consumido) = replay → 401 + revoca familia.
    const reuse = await request(app).post('/refresh').set('Cookie', cookie(token)).send();
    expect(reuse.status).toBe(401);
    expect(refreshTokenModel.revokeFamily).toHaveBeenCalledWith(familyId);

    // Consecuencia estricta: el token rotado (legítimo) TAMBIÉN queda inválido,
    // porque toda la familia fue revocada → re-login forzado.
    const afterRevoke = await request(app).post('/refresh').set('Cookie', cookie(rotated)).send();
    expect(afterRevoke.status).toBe(401);
  });

  test('token expirado (server-side) → 401 y revoca la familia', async () => {
    const { token, familyId } = await seedSession({ ttlMs: -1000 }); // ya vencido
    const res = await request(app).post('/refresh').set('Cookie', cookie(token)).send();
    expect(res.status).toBe(401);
    expect(refreshTokenModel.revokeFamily).toHaveBeenCalledWith(familyId);
  });

  test('multi-dispositivo: dos familias independientes; revocar una no afecta la otra', async () => {
    const a = await seedSession({ userId: 'u1' }); // dispositivo A
    const b = await seedSession({ userId: 'u1' }); // dispositivo B (misma cuenta)

    // Forzar reuse en A: usarlo dos veces.
    await request(app).post('/refresh').set('Cookie', cookie(a.token)).send();
    const reuseA = await request(app).post('/refresh').set('Cookie', cookie(a.token)).send();
    expect(reuseA.status).toBe(401); // familia A revocada

    // B sigue vivo: su primer refresh funciona.
    const okB = await request(app).post('/refresh').set('Cookie', cookie(b.token)).send();
    expect(okB.status).toBe(200);
  });
});
