/**
 * @file services/auth-service/tests/admin.test.js
 * @description Suite del panel admin de MIEMBROS (RBAC + CRUD), aislando la BD.
 *
 *   • 401 sin token · 403 sin rol STAFF_ROLES (GET/PATCH)
 *   • 200 listado (admin y staff) · 200 cambio de estado
 *   • 404 si el miembro no existe · 422 por validación de ruta
 *
 * La BD (Supabase) se aísla mockeando userModel; el RBAC se prueba de verdad
 * firmando JWT con el mismo secret/algoritmo que packages_shared/jwtVerify.
 */

'use strict';

// ── Entorno ANTES de requerir la app (environment.js hace process.exit(1)) ─────
process.env.NODE_ENV                  = 'test';
process.env.PORT                      = '3001';
process.env.SUPABASE_URL              = 'https://test.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_' + 'x'.repeat(30);
process.env.SUPABASE_DB_SCHEMA        = 'auth_service_db';
process.env.JWT_SECRET                = 'a'.repeat(64);
process.env.JWT_EXPIRES_IN            = '15m';
process.env.JWT_REFRESH_EXPIRES_IN    = '7d';
process.env.JWT_ALGORITHM             = 'HS512';
process.env.BCRYPT_ROUNDS             = '12';
process.env.ENCRYPTION_KEY            = 'f'.repeat(64); // length === 64
process.env.CORS_ALLOWED_ORIGINS      = 'http://localhost:5173';

const express = require('express');
const request = require('supertest');
const jwt     = require('jsonwebtoken');

jest.mock('../src/models/userModel');

const userModel         = require('../src/models/userModel');
const createAdminRoutes = require('../src/routes/adminRoutes');

const UUID = '11111111-1111-4111-8111-111111111111';

function signToken(role) {
  return jwt.sign(
    { sub: 'admin-1', jti: 'jti-1', role, email: 'admin@test.com' },
    process.env.JWT_SECRET,
    { algorithm: 'HS512' },
  );
}

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/v1/auth/admin', createAdminRoutes({ redisClient: null }));
  return app;
}

const app = buildApp();

beforeEach(() => {
  jest.clearAllMocks();
});

describe('auth-service · /api/v1/auth/admin/members (RBAC + CRUD)', () => {

  // ── RBAC ────────────────────────────────────────────────────────────────
  test('401 si no se envía token', async () => {
    const res = await request(app).get('/api/v1/auth/admin/members');
    expect(res.status).toBe(401);
  });

  test('403 si el rol NO está en STAFF_ROLES (GET /members)', async () => {
    const res = await request(app)
      .get('/api/v1/auth/admin/members')
      .set('Authorization', `Bearer ${signToken('miembro')}`);
    expect(res.status).toBe(403);
    expect(userModel.listMembers).not.toHaveBeenCalled();
  });

  test('403 si el rol NO está en STAFF_ROLES (PATCH /members/:id)', async () => {
    const res = await request(app)
      .patch(`/api/v1/auth/admin/members/${UUID}`)
      .set('Authorization', `Bearer ${signToken('miembro')}`)
      .send({ activo: false });
    expect(res.status).toBe(403);
    expect(userModel.setActive).not.toHaveBeenCalled();
  });

  // ── Listado ──────────────────────────────────────────────────────────────
  test('200 lista miembros para un admin', async () => {
    const members = [
      { id: UUID, nombre: 'Ana', email: 'ana@t.com', activo: true },
      { id: '22222222-2222-4222-8222-222222222222', nombre: 'Beto', email: 'b@t.com', activo: false },
    ];
    userModel.listMembers.mockResolvedValue(members);

    const res = await request(app)
      .get('/api/v1/auth/admin/members')
      .set('Authorization', `Bearer ${signToken('admin')}`);

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
    expect(userModel.listMembers).toHaveBeenCalledWith({ search: '' });
  });

  test('200 también para el rol staff', async () => {
    userModel.listMembers.mockResolvedValue([]);
    const res = await request(app)
      .get('/api/v1/auth/admin/members')
      .set('Authorization', `Bearer ${signToken('staff')}`);
    expect(res.status).toBe(200);
  });

  test('200 propaga el parámetro search al modelo', async () => {
    userModel.listMembers.mockResolvedValue([]);
    const res = await request(app)
      .get('/api/v1/auth/admin/members?search=ana')
      .set('Authorization', `Bearer ${signToken('admin')}`);
    expect(res.status).toBe(200);
    expect(userModel.listMembers).toHaveBeenCalledWith({ search: 'ana' });
  });

  // ── Cambio de estado ───────────────────────────────────────────────────────
  test('200 cambia el estado de un miembro (setActive)', async () => {
    const updated = { id: UUID, nombre: 'Ana', activo: false };
    userModel.setActive.mockResolvedValue(updated);

    const res = await request(app)
      .patch(`/api/v1/auth/admin/members/${UUID}`)
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send({ activo: false });

    expect(res.status).toBe(200);
    expect(res.body.data.activo).toBe(false);
    expect(userModel.setActive).toHaveBeenCalledWith(UUID, false);
  });

  test('404 si el miembro no existe (setActive devuelve null)', async () => {
    userModel.setActive.mockResolvedValue(null);

    const res = await request(app)
      .patch(`/api/v1/auth/admin/members/${UUID}`)
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send({ activo: true });

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/no encontrado/i);
  });

  // ── Validación de ruta ─────────────────────────────────────────────────────
  test('422 si el id no es UUID v4', async () => {
    const res = await request(app)
      .patch('/api/v1/auth/admin/members/no-es-uuid')
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send({ activo: true });
    expect(res.status).toBe(422);
    expect(userModel.setActive).not.toHaveBeenCalled();
  });

  test('422 si activo no es booleano', async () => {
    const res = await request(app)
      .patch(`/api/v1/auth/admin/members/${UUID}`)
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send({ activo: 'quizas' });
    expect(res.status).toBe(422);
    expect(userModel.setActive).not.toHaveBeenCalled();
  });
});
