/**
 * @file services/ai-service/tests/ssrfGuard.test.js
 * @description Pruebas del guard anti-SSRF compartido. Se usan IP literales y
 *              validaciones de protocolo/credenciales para no depender de DNS
 *              (la ruta de resolución DNS se ejercita en integración/runtime).
 */

'use strict';

const { assertSafePublicUrl, isBlockedIp, SsrfError } = require('../../../packages_shared/security/ssrfGuard');

describe('ssrfGuard — isBlockedIp', () => {
  test.each([
    ['127.0.0.1', true],   ['10.1.2.3', true],     ['172.16.0.1', true],
    ['172.31.255.255', true], ['192.168.1.1', true], ['169.254.169.254', true], // metadatos cloud
    ['100.64.0.1', true],  ['0.0.0.0', true],      ['::1', true],
    ['fe80::1', true],     ['fd00::1', true],      ['::ffff:10.0.0.1', true],   // IPv4-mapped privada
    ['8.8.8.8', false],    ['1.1.1.1', false],     ['172.15.0.1', false],       // 172.15 NO es privada
    ['172.32.0.1', false], ['93.184.216.34', false],
  ])('isBlockedIp(%s) === %s', (ip, expected) => {
    expect(isBlockedIp(ip)).toBe(expected);
  });
});

describe('ssrfGuard — assertSafePublicUrl (sin DNS: IP literales y validaciones)', () => {
  const reject = async (url, opts) => {
    await expect(assertSafePublicUrl(url, opts)).rejects.toBeInstanceOf(SsrfError);
  };

  test('bloquea metadatos del cloud (169.254.169.254)', async () => {
    await reject('https://169.254.169.254/latest/meta-data/');
  });
  test('bloquea loopback', async () => { await reject('https://127.0.0.1/admin'); });
  test('bloquea red privada 10/8', async () => { await reject('https://10.0.0.5:3003/internal'); });
  test('bloquea IPv6 loopback', async () => { await reject('https://[::1]/'); });
  test('rechaza protocolo no-https (http)', async () => { await reject('http://8.8.8.8/'); });
  test('rechaza esquemas peligrosos (file/gopher)', async () => {
    await reject('file:///etc/passwd');
    await reject('gopher://8.8.8.8/');
  });
  test('rechaza credenciales embebidas (bypass de host)', async () => {
    await reject('https://user:pass@8.8.8.8/');
  });
  test('rechaza URL malformada', async () => { await reject('no-soy-una-url'); });

  test('permite IP pública por https', async () => {
    const { ip } = await assertSafePublicUrl('https://8.8.8.8/imagen.jpg');
    expect(ip).toBe('8.8.8.8');
  });
  test('permite http si se habilita explícitamente', async () => {
    const { url } = await assertSafePublicUrl('http://1.1.1.1/x', { allowedProtocols: ['http:', 'https:'] });
    expect(url.protocol).toBe('http:');
  });
});
