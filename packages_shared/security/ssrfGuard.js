/**
 * @file packages_shared/security/ssrfGuard.js
 * @description Validador anti-SSRF para URLs PROVISTAS POR EL USUARIO.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP A10:2021 — Server-Side Request Forgery (SSRF)                ║
 * ║  Bloquea que un atacante haga que el backend solicite recursos       ║
 * ║  internos: loopback, redes privadas, link-local y el endpoint de     ║
 * ║  metadatos del cloud (169.254.169.254 en AWS/GCP/Azure).             ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * ⚠️  ÁMBITO DE USO — LEER:
 *   Este guard es EXCLUSIVO para URLs que vienen del usuario (p.ej. una URL de
 *   imagen para análisis multimodal). NUNCA envolver con él las llamadas
 *   internas service-to-service (fitness-service, etc.): esas resuelven a IPs
 *   PRIVADAS de la red de Docker/Railway y el guard las bloquearía por diseño.
 *
 * Cubre: protocolo (solo https por defecto), credenciales embebidas
 * (http://user@host), IP literales privadas/reservadas, y resolución DNS de
 * hostnames (valida TODAS las IPs resueltas). safeFetch además NO sigue
 * redirecciones (redirect:'error') para cerrar el bypass por redirect a interno.
 *
 * Limitación honesta (DNS rebinding TOCTOU): fetch resuelve DNS por su cuenta
 * tras la validación, así que un atacante con TTL 0 podría, en teoría, resolver
 * a pública en la validación y a privada en el fetch. La protección completa
 * exige fijar (pin) la IP validada en un agente que conecte a ella con el Host
 * original; queda documentado como endurecimiento adicional si el vector se
 * vuelve relevante. El bloqueo de redirects + validación mitiga el caso común.
 */

'use strict';

const dns = require('dns').promises;
const net = require('net');

class SsrfError extends Error {
  constructor(message) { super(message); this.name = 'SsrfError'; this.status = 400; }
}

/**
 * ¿La IP (v4/v6) pertenece a un rango privado, loopback, link-local o reservado?
 * @param {string} ip
 * @returns {boolean} true = bloquear
 */
function isBlockedIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    if (a === 0)   return true;                          // 0.0.0.0/8 "this host"
    if (a === 127) return true;                          // 127.0.0.0/8 loopback
    if (a === 10)  return true;                          // 10.0.0.0/8 privada
    if (a === 172 && b >= 16 && b <= 31) return true;    // 172.16.0.0/12 privada
    if (a === 192 && b === 168) return true;             // 192.168.0.0/16 privada
    if (a === 169 && b === 254) return true;             // 169.254.0.0/16 link-local (incl. metadatos)
    if (a === 100 && b >= 64 && b <= 127) return true;   // 100.64.0.0/10 CGNAT
    if (a >= 224) return true;                           // 224+ multicast/reservado
    return false;
  }
  if (net.isIPv6(ip)) {
    const low = ip.toLowerCase().replace(/^\[|\]$/g, '');
    if (low === '::1' || low === '::') return true;      // loopback / unspecified
    if (low.startsWith('fe80')) return true;             // link-local
    if (low.startsWith('fc') || low.startsWith('fd')) return true; // fc00::/7 unique-local
    const mapped = low.match(/::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/); // IPv4-mapped
    if (mapped) return isBlockedIp(mapped[1]);
    return false;
  }
  return true; // formato desconocido → bloquear por seguridad
}

/**
 * Valida que una URL de USUARIO sea segura para que el servidor la solicite.
 * Lanza SsrfError si no lo es.
 *
 * @param {string} rawUrl
 * @param {object} [opts]
 * @param {string[]} [opts.allowedProtocols=['https:']]
 * @returns {Promise<{ url: URL, ip: string }>} la URL parseada y la IP validada
 */
async function assertSafePublicUrl(rawUrl, { allowedProtocols = ['https:'] } = {}) {
  let u;
  try { u = new URL(String(rawUrl)); }
  catch { throw new SsrfError('URL inválida.'); }

  if (!allowedProtocols.includes(u.protocol)) {
    throw new SsrfError(`Protocolo no permitido: ${u.protocol}. Solo se aceptan ${allowedProtocols.join(', ')}.`);
  }
  // http://usuario:pass@host — truco para confundir el parseo del host.
  if (u.username || u.password) {
    throw new SsrfError('URLs con credenciales embebidas no están permitidas.');
  }

  const host = u.hostname.replace(/^\[|\]$/g, ''); // quitar corchetes de IPv6

  // Host que ya es IP literal: validar directamente.
  if (net.isIP(host)) {
    if (isBlockedIp(host)) throw new SsrfError('La URL apunta a una IP privada o reservada.');
    return { url: u, ip: host };
  }

  // Hostname: resolver DNS y validar TODAS las IPs (v4 y v6).
  let records;
  try { records = await dns.lookup(host, { all: true }); }
  catch { throw new SsrfError('El host no se pudo resolver.'); }

  if (!records || records.length === 0) throw new SsrfError('El host no se pudo resolver.');
  for (const r of records) {
    if (isBlockedIp(r.address)) {
      throw new SsrfError('El host resuelve a una IP privada o reservada.');
    }
  }
  return { url: u, ip: records[0].address };
}

/**
 * fetch endurecido para URLs de usuario: valida anti-SSRF, NO sigue redirects
 * (redirect:'error' cierra el bypass a interno), y aplica timeout.
 *
 * @param {string} rawUrl
 * @param {object} [opts]
 * @param {number} [opts.timeoutMs=4000]
 * @param {string[]} [opts.allowedProtocols=['https:']]
 * @param {object} [opts.fetchOptions={}]  - headers, method, etc. (redirect se fuerza a 'error')
 * @returns {Promise<Response>}
 */
async function safeFetch(rawUrl, { timeoutMs = 4000, allowedProtocols = ['https:'], fetchOptions = {} } = {}) {
  const { url } = await assertSafePublicUrl(rawUrl, { allowedProtocols });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...fetchOptions,
      redirect: 'error',            // ← no seguir redirecciones (anti-SSRF por redirect)
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { assertSafePublicUrl, safeFetch, isBlockedIp, SsrfError };
