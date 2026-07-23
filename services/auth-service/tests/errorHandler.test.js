/**
 * @file services/auth-service/tests/errorHandler.test.js
 * @description Verifica el manejador de errores compartido en modo PRODUCCIÓN:
 *              no fuga de detalles internos (CWE-209) manteniendo mensajes de
 *              negocio 4xx legibles.
 *
 * NODE_ENV se fija a 'production' ANTES de requerir el módulo; Jest aísla el
 * registro de módulos por archivo, así que no afecta a las demás suites.
 */

'use strict';

process.env.NODE_ENV = 'production';

const { createErrorHandler } = require('../../../packages_shared/security/errorHandler');

const handler = createErrorHandler('test-service');

function mockRes() {
  return {
    statusCode: null, body: null,
    status(c) { this.statusCode = c; return this; },
    json(b)   { this.body = b; return this; },
    setHeader() {}, getHeader() { return null; },
  };
}
const req = { method: 'GET', path: '/x', headers: {}, ip: '1.2.3.4' };
const run = (err) => { const res = mockRes(); handler(err, req, res, () => {}); return res; };

describe('errorHandler en producción — no fuga de internos (CWE-209)', () => {
  test('error 5xx con .statusCode NO refleja el mensaje interno', () => {
    const err = Object.assign(new Error('connect ECONNREFUSED 10.0.0.5:6379'), { statusCode: 500 });
    const res = run(err);
    expect(res.statusCode).toBe(500);
    expect(res.body.error).toBe('Ocurrió un error interno. Por favor, intenta más tarde.');
    expect(res.body.error).not.toContain('ECONNREFUSED');
  });

  test('error 4xx de negocio SÍ conserva su mensaje legible', () => {
    const err = Object.assign(new Error('Email inválido.'), { status: 400 });
    const res = run(err);
    expect(res.statusCode).toBe(400);
    expect(res.body.error).toBe('Email inválido.');
  });

  test('Error genérico (sin status) → 500 genérico', () => {
    const res = run(new Error('DB password is hunter2 at /app/src/db.js:42'));
    expect(res.statusCode).toBe(500);
    expect(res.body.error).toBe('Ocurrió un error interno. Por favor, intenta más tarde.');
    expect(res.body.error).not.toContain('hunter2');
  });

  test('JsonWebTokenError → 401 con mensaje genérico', () => {
    const err = Object.assign(new Error('invalid signature'), { name: 'JsonWebTokenError' });
    const res = run(err);
    expect(res.statusCode).toBe(401);
    expect(res.body.error).toBe('Token de autenticación inválido.');
  });

  test('error de Postgres (2xxxx) no expone el detalle del schema', () => {
    const err = Object.assign(new Error('relation "usuarios" violates'), { code: '23505', detail: 'Key (email)=...' });
    const res = run(err);
    expect(res.statusCode).toBe(500);
    expect(res.body.error).toBe('Error al procesar la solicitud en la base de datos.');
    expect(JSON.stringify(res.body)).not.toContain('usuarios');
  });
});
