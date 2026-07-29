/**
 * @file services/auth-service/tests/jwtAsymmetric.test.js
 * @description A04-1 — verificación JWT en CONVIVENCIA: el verificador acepta
 * tokens firmados con la clave PRIVADA nueva (RS256) Y con el secreto simétrico
 * viejo (HS512), sin abrir la puerta a confusión de algoritmo (RS/HS).
 */

'use strict';

// Env ANTES de requerir jwtVerify (lee las claves al cargar el módulo).
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'a'.repeat(64);
process.env.JWT_ALGORITHM = 'HS512';

const crypto = require('crypto');
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const pubPem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
const privPem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();

// La clave pública se inyecta en base64 (ruta recomendada en env vars).
process.env.JWT_PUBLIC_KEY = Buffer.from(pubPem).toString('base64');
process.env.JWT_VERIFY_ALGORITHMS = 'RS256';

const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const { createJwtVerifyMiddleware } = require('../../../packages_shared/security/jwtVerify');

const CLAIMS = { sub: 'u1', jti: 'j1', role: 'miembro', email: 'x@y.com' };

function buildApp() {
  const app = express();
  app.get('/p', createJwtVerifyMiddleware({ redisClient: null }), (req, res) =>
    res.json({ id: req.user.id }));
  // Mapea errores JWT (next(err)) a 401 como el errorHandler central.
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => res.status(401).json({ error: err.name }));
  return app;
}

afterAll(() => { delete process.env.JWT_PUBLIC_KEY; });

describe('A04-1 · JWT convivencia asimétrica + simétrica', () => {
  test('ACEPTA token RS256 (clave privada nueva)', async () => {
    const token = jwt.sign(CLAIMS, privPem, { algorithm: 'RS256', expiresIn: '5m' });
    const res = await request(buildApp()).get('/p').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe('u1');
  });

  test('SIGUE aceptando token HS512 viejo (convivencia, sin invalidar de golpe)', async () => {
    const token = jwt.sign(CLAIMS, process.env.JWT_SECRET, { algorithm: 'HS512', expiresIn: '5m' });
    const res = await request(buildApp()).get('/p').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });

  test('RECHAZA HS512 firmado con la CLAVE PÚBLICA como secreto (anti-confusión RS/HS)', async () => {
    const token = jwt.sign(CLAIMS, pubPem, { algorithm: 'HS512', expiresIn: '5m' });
    const res = await request(buildApp()).get('/p').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
  });

  test('RECHAZA token RS256 expirado', async () => {
    const token = jwt.sign(CLAIMS, privPem, { algorithm: 'RS256', expiresIn: -10 });
    const res = await request(buildApp()).get('/p').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
  });

  test('RECHAZA alg:none', async () => {
    const token = jwt.sign(CLAIMS, '', { algorithm: 'none' });
    const res = await request(buildApp()).get('/p').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
  });
});
