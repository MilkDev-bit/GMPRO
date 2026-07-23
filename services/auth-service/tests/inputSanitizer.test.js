/**
 * @file services/auth-service/tests/inputSanitizer.test.js
 * @description Pruebas del sanitizador compartido: bypass Unicode (orden de
 *              normalización), caracteres de control, prototype pollution,
 *              límite de profundidad y no-regresión con entrada legítima.
 */

'use strict';

const { sanitizeValue } = require('../../../packages_shared/security/inputSanitizer');

describe('inputSanitizer — hardening', () => {
  test('bypass Unicode: ＜ fullwidth NO reintroduce un tag tras el escape', () => {
    // Antes del fix, NFKC corría al final → producía <img ...> sin escapar.
    const { sanitized } = sanitizeValue('＜img src=x onerror=alert(1)＞');
    expect(sanitized).not.toContain('<');
    expect(sanitized).not.toContain('onerror=');   // el tag fue neutralizado
    expect(sanitized.toLowerCase()).not.toContain('<img');
  });

  test('script fullwidth se elimina, no se convierte en <script> ejecutable', () => {
    const { sanitized } = sanitizeValue('＜script＞alert(1)＜/script＞');
    expect(sanitized).not.toContain('<script');
    expect(sanitized).not.toContain('<');
  });

  test('elimina caracteres de control (null-byte, bell) y preserva \\t\\n\\r', () => {
    const r1 = sanitizeValue('a\x00b\x07c');       // null + bell
    expect(r1.sanitized).toBe('abc');
    const r2 = sanitizeValue('linea1\nlinea2\ttab');
    expect(r2.sanitized).toContain('\n');
    expect(r2.sanitized).toContain('\t');
  });

  test('prototype pollution: clave __proto__ se descarta y NO contamina Object', () => {
    // JSON.parse crea __proto__ como clave PROPIA (el ataque real), a diferencia
    // del literal {__proto__:...} que setea el prototipo.
    const payload = JSON.parse('{"__proto__":{"admin":true},"name":"ok"}');
    const { sanitized, threats } = sanitizeValue(payload);

    expect(threats.some((t) => t.startsWith('PROTOTYPE_POLLUTION'))).toBe(true);
    expect(sanitized.name).toBe('ok');
    expect(sanitized.admin).toBeUndefined();
    expect(({}).admin).toBeUndefined();            // Object.prototype intacto
    expect(Object.prototype.admin).toBeUndefined();
  });

  test('bloquea claves constructor / prototype', () => {
    const payload = JSON.parse('{"constructor":{"x":1},"prototype":{"y":2},"ok":1}');
    const { sanitized, threats } = sanitizeValue(payload);
    expect(threats.filter((t) => t.startsWith('PROTOTYPE_POLLUTION')).length).toBe(2);
    expect(sanitized.ok).toBe(1);
    expect(sanitized.constructor).toBe(Object);    // el constructor nativo, no el inyectado
  });

  test('anidamiento profundo → DEPTH_EXCEEDED (anti-DoS por recursión)', () => {
    let deep = 'x';
    for (let i = 0; i < 40; i++) deep = [deep];    // 40 niveles de arrays
    const { threats } = sanitizeValue(deep);
    expect(threats.some((t) => t.startsWith('DEPTH_EXCEEDED'))).toBe(true);
  });

  test('detecta operadores NoSQL en claves ($)', () => {
    const { threats } = sanitizeValue(JSON.parse('{"email":{"$ne":null}}'));
    expect(threats.some((t) => t.startsWith('NOSQL_INJECTION'))).toBe(true);
  });

  test('no-regresión: entrada legítima se preserva', () => {
    const { sanitized, threats } = sanitizeValue({ name: 'Juan Pérez', email: 'a@b.com', edad: 30, activo: true });
    expect(threats).toHaveLength(0);
    expect(sanitized.name).toBe('Juan Pérez');
    expect(sanitized.email).toBe('a@b.com');
    expect(sanitized.edad).toBe(30);
    expect(sanitized.activo).toBe(true);
  });
});
