/**
 * @file services/auth-service/tests/loggerRedaction.test.js
 * @description Verifica la redacción de datos sensibles del logger compartido
 *              (CWE-532): por clave sensible, por patrón de valor, anidado, y
 *              end-to-end capturando la salida real del logger en producción.
 */

'use strict';

// Producción → formato JSON (más fácil de aseverar en la captura E2E).
process.env.NODE_ENV = 'production';

const { transports } = require('winston');
const { Writable }   = require('stream');
const {
  redactValue, __resetLoggerCache, createServiceLogger,
} = require('../../../packages_shared/security/logger');

const redactObj = (o) => redactValue(o, 1, new WeakSet());

describe('logger — redacción de datos sensibles (unit)', () => {
  test('redacta valores de claves sensibles', () => {
    const r = redactObj({ password: 'hunter2', authorization: 'Bearer abc', ok: 'visible' });
    expect(r.password).toBe('[REDACTED]');
    expect(r.authorization).toBe('[REDACTED]');
    expect(r.ok).toBe('visible');
  });

  test('redacta secretos por patrón aunque la clave no sea sensible', () => {
    const jwt = 'eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJ1MSJ9.abcDEF123_signature';
    const r = redactObj({ nota: `mi token es ${jwt}`, sk: 'usa sk_live_ABCDEF123456 aqui' });
    expect(r.nota).toContain('[REDACTED]');
    expect(r.nota).not.toContain(jwt);
    expect(r.sk).toContain('[REDACTED]');
    expect(r.sk).not.toContain('sk_live_ABCDEF123456');
  });

  test('redacta en estructuras anidadas y arrays sin tocar lo legítimo', () => {
    const r = redactObj({ user: { name: 'Juan', password: 'x' }, list: [{ token: 't' }, { edad: 30 }] });
    expect(r.user.name).toBe('Juan');
    expect(r.user.password).toBe('[REDACTED]');
    expect(r.list[0].token).toBe('[REDACTED]');
    expect(r.list[1].edad).toBe(30);
  });

  test('tolera referencias circulares', () => {
    const a = { password: 'p' }; a.self = a;
    const r = redactObj(a);
    expect(r.password).toBe('[REDACTED]');
    expect(r.self).toBe('[CIRCULAR]');
  });

  test('no muta el objeto original del caller', () => {
    const original = { password: 'hunter2' };
    redactObj(original);
    expect(original.password).toBe('hunter2'); // el original intacto
  });
});

describe('logger — end-to-end (captura de stdout real)', () => {
  test('un log con password sale enmascarado como [REDACTED]', async () => {
    __resetLoggerCache();
    const logger = createServiceLogger('test-redaction');

    // Transport de stream en memoria: recibe la línea YA formateada por el
    // pipeline del logger (redactFormat → json). Determinista, sin depender de
    // cómo winston escriba a consola bajo jest.
    let captured = '';
    const mem = new Writable({ write(chunk, _enc, cb) { captured += chunk.toString(); cb(); } });
    const memTransport = new transports.Stream({ stream: mem });
    logger.add(memTransport);

    logger.info('login recibido', {
      email: 'a@b.com',
      password: 'SuperSecret123!',
      authorization: 'Bearer eyJhbGciOiJI.payloadXYZ.sigABC',
    });
    await new Promise((r) => setImmediate(r)); // flush del stream
    logger.remove(memTransport);

    expect(captured).toContain('[REDACTED]');
    expect(captured).not.toContain('SuperSecret123!');
    expect(captured).not.toContain('eyJhbGciOiJI.payloadXYZ.sigABC');
    expect(captured).toContain('a@b.com');       // dato no sensible se conserva
  });
});
