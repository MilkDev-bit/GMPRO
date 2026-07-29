/**
 * @file services/ai-service/tests/safeImageFetch.test.js
 * @description A01-3 — fetchUserImage rechaza URLs internas/privadas/metadata y
 * protocolos no https, y permite URLs externas https legítimas.
 */

'use strict';

const { fetchUserImage } = require('../src/services/safeImageFetch');
const { SsrfError } = require('../../../packages_shared/security/ssrfGuard');

describe('A01-3 · fetchUserImage (SSRF-guarded)', () => {
  const realFetch = global.fetch;
  afterEach(() => { global.fetch = realFetch; });

  test.each([
    ['loopback',            'https://127.0.0.1/x.jpg'],
    ['privada 10/8',        'https://10.0.0.5/x.jpg'],
    ['privada 172.16/12',   'https://172.16.4.4/x.jpg'],
    ['privada 192.168/16',  'https://192.168.1.10/x.jpg'],
    ['metadata cloud',      'https://169.254.169.254/latest/meta-data/'],
    ['IPv6 loopback',       'https://[::1]/x.jpg'],
    ['http no permitido',   'http://93.184.216.34/x.jpg'],
    ['credenciales embebidas', 'https://user:pass@93.184.216.34/x.jpg'],
  ])('rechaza %s', async (_name, url) => {
    await expect(fetchUserImage(url)).rejects.toBeInstanceOf(SsrfError);
  });

  test('NO llama a fetch cuando la URL es interna (se corta antes)', async () => {
    global.fetch = jest.fn();
    await expect(fetchUserImage('https://127.0.0.1/x.jpg')).rejects.toBeInstanceOf(SsrfError);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test('permite URL externa https (IP pública) y valida tipo/tamaño', async () => {
    global.fetch = jest.fn(async () => ({
      ok: true,
      status: 200,
      headers: { get: () => 'image/jpeg' },
      arrayBuffer: async () => new ArrayBuffer(256),
    }));
    const out = await fetchUserImage('https://93.184.216.34/logo.jpg');
    expect(out.contentType).toBe('image/jpeg');
    expect(out.buffer.length).toBe(256);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('rechaza contenido que no es imagen', async () => {
    global.fetch = jest.fn(async () => ({
      ok: true, status: 200,
      headers: { get: () => 'text/html' },
      arrayBuffer: async () => new ArrayBuffer(10),
    }));
    await expect(fetchUserImage('https://93.184.216.34/x')).rejects.toBeInstanceOf(SsrfError);
  });

  test('rechaza imagen que excede el tamaño máximo', async () => {
    global.fetch = jest.fn(async () => ({
      ok: true, status: 200,
      headers: { get: () => 'image/png' },
      arrayBuffer: async () => new ArrayBuffer(64),
    }));
    await expect(fetchUserImage('https://93.184.216.34/big.png', { maxBytes: 10 }))
      .rejects.toBeInstanceOf(SsrfError);
  });
});
