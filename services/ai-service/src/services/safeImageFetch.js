/**
 * @file services/ai-service/src/services/safeImageFetch.js
 * @description A01-3 — ÚNICA vía permitida para descargar contenido desde una URL
 * PROVISTA POR EL USUARIO (p. ej. imagen para análisis multimodal).
 *
 * Cablea el guard anti-SSRF ya existente (packages_shared/security/ssrfGuard):
 *   • assertSafePublicUrl bloquea loopback (127/8, ::1), privadas RFC1918
 *     (10/8, 172.16/12, 192.168/16), link-local/metadata (169.254.169.254),
 *     CGNAT, IPv6 ULA/mapeadas y valida TODAS las IPs resueltas por DNS.
 *   • safeFetch fuerza `redirect: 'error'` (no seguir redirects a interno) y timeout.
 * Además valida tipo (imagen) y tamaño máximo.
 *
 * ⚠ REGLA: NINGÚN flujo debe hacer `fetch()` de una URL de usuario sin pasar por
 *   aquí. Hoy no existe endpoint que reciba URLs de usuario; cuando se añada el
 *   análisis multimodal por URL, DEBE invocar `fetchUserImage`.
 */

'use strict';

const { safeFetch, SsrfError } = require('../../../../packages_shared/security/ssrfGuard');

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

// Whitelist de dominios permitidos para descargar imágenes de usuario.
// Configurable por env (coma-separada), p.ej.:
//   AI_IMAGE_ALLOWED_HOSTS="storage.googleapis.com,cdn.gympro.com"
// Vacía = sin whitelist (solo se aplica el bloqueo de IPs privadas del guard);
// en producción se RECOMIENDA definirla para restringir a tus CDNs/buckets.
const DEFAULT_ALLOWED_HOSTS = String(process.env.AI_IMAGE_ALLOWED_HOSTS || '')
  .split(',')
  .map((h) => h.trim())
  .filter(Boolean);

/**
 * Descarga una imagen desde una URL de usuario de forma segura.
 * @param {string} rawUrl
 * @param {object} [opts]
 * @param {number} [opts.maxBytes]
 * @param {string[]} [opts.allowedHosts]  - whitelist de dominios; por defecto la
 *   de env AI_IMAGE_ALLOWED_HOSTS. Si está vacía, solo aplica el bloqueo de IPs privadas.
 * @returns {Promise<{buffer: Buffer, contentType: string}>}
 * @throws {SsrfError} si la URL es interna/privada, el protocolo no es https, o
 *   el contenido no es una imagen permitida / excede el tamaño.
 */
async function fetchUserImage(rawUrl, { maxBytes = MAX_BYTES, allowedHosts = DEFAULT_ALLOWED_HOSTS } = {}) {
  const res = await safeFetch(rawUrl, {
    timeoutMs: 4000,
    allowedProtocols: ['https:'], // solo https para URLs de usuario
    allowedHosts,                 // whitelist de dominios (env AI_IMAGE_ALLOWED_HOSTS)
    fetchOptions: { method: 'GET' },
  });

  if (!res.ok) throw new SsrfError(`Descarga fallida (HTTP ${res.status}).`);

  const contentType = String(res.headers.get('content-type') || '')
    .split(';')[0].trim().toLowerCase();
  if (!ALLOWED_TYPES.includes(contentType)) {
    throw new SsrfError(`Tipo de contenido no permitido: ${contentType || 'desconocido'}.`);
  }

  const buffer = Buffer.from(await res.arrayBuffer());
  if (buffer.length > maxBytes) throw new SsrfError('La imagen excede el tamaño máximo permitido.');

  return { buffer, contentType };
}

module.exports = { fetchUserImage, MAX_BYTES, ALLOWED_TYPES };
