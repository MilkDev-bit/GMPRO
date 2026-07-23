/**
 * @file services/auth-service/tests/integration/refreshConcurrency.integration.test.js
 * @description INTEGRACIÓN contra Postgres REAL: prueba de CONCURRENCIA del
 *              /refresh. Dispara N peticiones simultáneas (Promise.all) con el
 *              MISMO token válido y confirma que SOLO UNA rota y que el reuse
 *              revoca la familia completa.
 *
 * FIDELIDAD:
 *   · Corre el HANDLER REAL `authController.refreshToken` (misma lógica de
 *     decisión: reuse detection, consumo atómico, revocación de familia).
 *   · refreshTokenModel se respalda con `pg` DIRECTO contra el Postgres efímero,
 *     ejecutando el MISMO SQL que compila la cadena supabase-js del modelo real
 *     (`UPDATE ... WHERE is_consumed=false RETURNING id`). La garantía de
 *     atomicidad es una propiedad de Postgres (row lock), idéntica por ambos
 *     transportes; por eso este es el test autoritativo del race condition.
 *   · Solo se mockea la identidad (userModel.findById), irrelevante para la carrera.
 *
 * Se SALTA automáticamente si no hay DATABASE_URL (p. ej. en la suite unitaria):
 * así `npm test` normal no falla sin una BD.
 */

'use strict';

// ── Entorno ANTES de requerir nada (environment.js valida al cargar) ─────────
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
process.env.REFRESH_TOKEN_TTL_DAYS  = '30';

const HAS_DB = !!process.env.DATABASE_URL;

// ── refreshTokenModel respaldado por pg (mismo SQL que el modelo real) ───────
jest.mock('../../src/models/refreshTokenModel', () => {
  if (!process.env.DATABASE_URL) return {}; // suite saltada; nunca se invoca
  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 20 });
  return {
    __pool: pool,
    issue: async ({ userId, tokenHash, familyId, expiresAt, deviceInfo = null, ipAddress = null }) => {
      const r = await pool.query(
        `INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at, device_info, ip_address)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, family_id, expires_at`,
        [userId, familyId, tokenHash, expiresAt, deviceInfo, ipAddress]
      );
      return r.rows[0];
    },
    findByHash: async (h) => {
      const r = await pool.query(
        `SELECT id, user_id, family_id, is_consumed, expires_at, revoked_at
         FROM refresh_tokens WHERE token_hash = $1 LIMIT 1`, [h]
      );
      return r.rows[0] || null;
    },
    // Sección crítica: SOLO consume si aún estaba sin consumir y sin revocar.
    consumeAtomically: async (id) => {
      const r = await pool.query(
        `UPDATE refresh_tokens SET is_consumed = TRUE, consumed_at = NOW()
         WHERE id = $1 AND is_consumed = FALSE AND revoked_at IS NULL RETURNING id`, [id]
      );
      return r.rowCount === 1;
    },
    revokeFamily: async (familyId) => {
      const r = await pool.query(
        `UPDATE refresh_tokens SET revoked_at = NOW()
         WHERE family_id = $1 AND revoked_at IS NULL RETURNING id`, [familyId]
      );
      return r.rowCount;
    },
    revokeAllForUser: async (userId) => {
      const r = await pool.query(
        `UPDATE refresh_tokens SET revoked_at = NOW()
         WHERE user_id = $1 AND revoked_at IS NULL RETURNING id`, [userId]
      );
      return r.rowCount;
    },
    // Candado BOLA: revoca SOLO si la familia pertenece al userId.
    revokeFamilyForUser: async (userId, familyId) => {
      const r = await pool.query(
        `UPDATE refresh_tokens SET revoked_at = NOW()
         WHERE user_id = $1 AND family_id = $2 AND revoked_at IS NULL RETURNING id`,
        [userId, familyId]
      );
      return r.rowCount;
    },
    listActiveSessionsForUser: async (userId) => {
      const r = await pool.query(
        `SELECT family_id, device_info, ip_address, created_at, expires_at
         FROM refresh_tokens WHERE user_id = $1 AND revoked_at IS NULL
         ORDER BY created_at DESC`, [userId]
      );
      const byFamily = new Map();
      for (const row of r.rows) {
        if (!byFamily.has(row.family_id)) {
          byFamily.set(row.family_id, {
            familyId: row.family_id, device: row.device_info, ip: row.ip_address,
            started: row.created_at, lastActive: row.created_at, expiresAt: row.expires_at,
          });
        }
      }
      return [...byFamily.values()];
    },
  };
});

jest.mock('../../src/models/userModel', () => ({
  findById: async (id) => ({ id, email: 'user@x.com', rol: 'miembro', activo: true }),
  recordSuccessfulLogin: async () => {},
}));
jest.mock('../../src/services/emailService', () => ({}));

const express      = require('express');
const cookieParser = require('cookie-parser');
const request      = require('supertest');
const crypto       = require('crypto');
const jwt          = require('jsonwebtoken');

// Nota: estos require se resuelven aunque HAS_DB sea false; el mock devuelve {}.
const authController    = require('../../src/controllers/authController');
const sessionController = require('../../src/controllers/sessionController');
const refreshTokenModel = require('../../src/models/refreshTokenModel');
const { createJwtVerifyMiddleware } = require('../../../../packages_shared/security/jwtVerify');

// Pool compartido por todos los bloques; se cierra una sola vez al final.
const pgPool = () => refreshTokenModel.__pool;
async function ensureSchema() {
  // DDL autocontenida (sin FK a usuarios; gen_random_uuid es core en PG13+).
  await pgPool().query(`
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id     UUID NOT NULL,
      family_id   UUID NOT NULL,
      token_hash  VARCHAR(64) NOT NULL UNIQUE,
      is_consumed BOOLEAN NOT NULL DEFAULT FALSE,
      expires_at  TIMESTAMPTZ NOT NULL,
      device_info VARCHAR(255),
      ip_address  VARCHAR(64),
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      consumed_at TIMESTAMPTZ,
      revoked_at  TIMESTAMPTZ
    );`);
}
if (HAS_DB) {
  afterAll(async () => { await pgPool().end(); }); // cierra el pool tras TODOS los bloques
}

const USER_ID = '11111111-1111-1111-1111-111111111111';

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use(cookieParser());
  app.post('/refresh', authController.refreshToken);
  return app;
}
const cookie = (t) => ['refreshToken=' + t];

async function seedSession({ ttlMs = 30 * 24 * 60 * 60_000 } = {}) {
  const token = crypto.randomBytes(64).toString('base64url');
  const hash  = crypto.createHash('sha256').update(token).digest('hex');
  const familyId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + ttlMs).toISOString();
  await refreshTokenModel.issue({ userId: USER_ID, tokenHash: hash, familyId, expiresAt });
  return { token, hash, familyId };
}

// describe.skip si no hay BD (suite unitaria normal).
(HAS_DB ? describe : describe.skip)('INTEGRACIÓN — concurrencia de /refresh contra Postgres real', () => {
  let app;
  const pool = () => refreshTokenModel.__pool;

  beforeAll(ensureSchema);
  beforeEach(async () => { await pool().query('TRUNCATE refresh_tokens'); app = buildApp(); });

  // ── DB puro: N consumos atómicos concurrentes del MISMO id → exactamente 1 ──
  test('consumeAtomically bajo carrera real: exactamente 1 gana de N concurrentes', async () => {
    const { hash } = await seedSession();
    const { rows } = await pool().query('SELECT id FROM refresh_tokens WHERE token_hash=$1', [hash]);
    const id = rows[0].id;

    const N = 20;
    const results = await Promise.all(
      Array.from({ length: N }, () => refreshTokenModel.consumeAtomically(id))
    );
    const winners = results.filter(Boolean).length;
    expect(winners).toBe(1);                    // solo uno adquirió el row lock
    expect(results.length - winners).toBe(N - 1);
  });

  // ── HTTP real: N peticiones /refresh simultáneas con el mismo token ─────────
  test('N /refresh simultáneos con el mismo token: 1 rota (200), el resto 401', async () => {
    const { token, familyId } = await seedSession();

    const N = 20;
    const results = await Promise.all(
      Array.from({ length: N }, () =>
        request(app).post('/refresh').set('Cookie', cookie(token)).send())
    );
    const statuses = results.map((r) => r.status);
    const ok  = statuses.filter((s) => s === 200).length;
    const bad = statuses.filter((s) => s === 401).length;

    expect(ok).toBe(1);       // SOLO una rotación exitosa
    expect(bad).toBe(N - 1);  // el resto rechazado

    // El token original quedó consumido en la BD.
    const { rows } = await pool().query(
      'SELECT is_consumed FROM refresh_tokens WHERE family_id=$1 AND token_hash=$2',
      [familyId, crypto.createHash('sha256').update(token).digest('hex')]
    );
    expect(rows[0].is_consumed).toBe(true);
  });

  // ── Reuse determinista → revoca TODA la familia (mitiga robo) ───────────────
  test('reuse del token consumido revoca la familia completa', async () => {
    const { token, familyId } = await seedSession();

    // 1er uso legítimo (rota).
    const first = await request(app).post('/refresh').set('Cookie', cookie(token)).send();
    expect(first.status).toBe(200);

    // 2º uso del MISMO token (ya consumido) → reuse → 401 + revoca familia.
    const reuse = await request(app).post('/refresh').set('Cookie', cookie(token)).send();
    expect(reuse.status).toBe(401);

    // Toda la familia quedó revocada en la BD (incluido el token rotado).
    const { rows } = await pool().query(
      'SELECT COUNT(*)::int AS activos FROM refresh_tokens WHERE family_id=$1 AND revoked_at IS NULL',
      [familyId]
    );
    expect(rows[0].activos).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Candado BOLA/IDOR de gestión de sesiones contra Postgres REAL.
// User B intenta revocar (DELETE) la familia de User A → 404 y, verificado a
// nivel SQL, la sesión de A permanece INTACTA (revoked_at IS NULL).
// ═══════════════════════════════════════════════════════════════════════════
(HAS_DB ? describe : describe.skip)('INTEGRACIÓN — candado BOLA de sesiones (Postgres real)', () => {
  let app;
  const pool = () => refreshTokenModel.__pool;

  const USER_A   = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const USER_B   = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const FAMILY_A = 'a1a1a1a1-1111-4111-8111-a1a1a1a1a1a1';
  const FAMILY_B = 'b2b2b2b2-2222-4222-8222-b2b2b2b2b2b2';

  function buildSessionApp() {
    const a = express();
    a.use(express.json());
    const jwtVerify = createJwtVerifyMiddleware(); // verificación real de JWT
    a.get('/sessions',              jwtVerify, sessionController.listSessions);
    a.delete('/sessions/:familyId', jwtVerify, sessionController.revokeSession);
    return a;
  }
  const signToken = (userId) => jwt.sign(
    { sub: userId, role: 'miembro', jti: crypto.randomUUID(), email: `${userId}@x.com` },
    process.env.JWT_SECRET, { algorithm: process.env.JWT_ALGORITHM, expiresIn: '5m' });
  const bearer = (uid) => ({ Authorization: `Bearer ${signToken(uid)}` });

  async function seed(userId, familyId) {
    const token = crypto.randomBytes(64).toString('base64url');
    const hash  = crypto.createHash('sha256').update(token).digest('hex');
    await refreshTokenModel.issue({
      userId, tokenHash: hash, familyId,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60_000).toISOString(),
      deviceInfo: 'Test UA', ipAddress: '1.2.3.4',
    });
  }

  beforeAll(ensureSchema);
  beforeEach(async () => {
    await pool().query('TRUNCATE refresh_tokens');
    await seed(USER_A, FAMILY_A);   // sesión de A
    await seed(USER_B, FAMILY_B);   // sesión de B
    app = buildSessionApp();
  });

  test('IDOR: User B intenta revocar la familia de User A → 404 y sigue intacta en la BD', async () => {
    const res = await request(app)
      .delete(`/sessions/${FAMILY_A}`)
      .set(bearer(USER_B))
      .send();

    expect(res.status).toBe(404); // el candado por user_id no encontró nada que revocar

    // Verificación DIRECTA a nivel SQL: la sesión de A sigue ACTIVA.
    const a = await pool().query('SELECT revoked_at FROM refresh_tokens WHERE family_id=$1', [FAMILY_A]);
    expect(a.rows.length).toBeGreaterThan(0);
    expect(a.rows.every((r) => r.revoked_at === null)).toBe(true);
  });

  test('control positivo: User A revoca su propia familia → 200; la de B nunca se toca', async () => {
    const res = await request(app)
      .delete(`/sessions/${FAMILY_A}`)
      .set(bearer(USER_A))
      .send();
    expect(res.status).toBe(200);

    const a = await pool().query('SELECT revoked_at FROM refresh_tokens WHERE family_id=$1', [FAMILY_A]);
    expect(a.rows.every((r) => r.revoked_at !== null)).toBe(true);   // A revocada

    const b = await pool().query('SELECT revoked_at FROM refresh_tokens WHERE family_id=$1', [FAMILY_B]);
    expect(b.rows.every((r) => r.revoked_at === null)).toBe(true);   // B intacta
  });

  test('GET /sessions solo devuelve las sesiones del usuario autenticado', async () => {
    const res = await request(app).get('/sessions').set(bearer(USER_A)).send();
    expect(res.status).toBe(200);
    expect(res.body.data.total).toBe(1);
    expect(res.body.data.sessions[0].familyId).toBe(FAMILY_A);
  });
});
