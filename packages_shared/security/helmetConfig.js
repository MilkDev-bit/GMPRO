/**
 * @file packages_shared/security/helmetConfig.js
 * @description Cabeceras de seguridad HTTP mediante Helmet.js
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP Top 10 Mitigaciones:                                         ║
 * ║  • A05:2021 — Security Misconfiguration                             ║
 * ║    → Helmet configura cabeceras que el servidor no envía por defecto ║
 * ║  • A03:2021 — Injection (XSS via headers)                           ║
 * ║    → Content-Security-Policy previene ejecución de scripts externos  ║
 * ║  • A02:2021 — Cryptographic Failures                                ║
 * ║    → HSTS fuerza HTTPS y previene downgrade a HTTP                  ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * Referencias:
 *   • https://owasp.org/www-project-secure-headers/
 *   • https://helmetjs.github.io/
 *   • https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
 */

'use strict';

const helmet = require('helmet');

/**
 * Construye la configuración de Helmet personalizada para los microservicios.
 *
 * Los microservicios GymPro son APIs REST puras (sin renderizado de HTML),
 * por lo que muchas directivas CSP son innecesarias. La configuración es
 * más restrictiva que la de una aplicación web estándar.
 *
 * @param {object} [options]
 * @param {boolean} [options.isApiOnly=true]    - Si true, aplica CSP maximalista
 * @param {string[]} [options.allowedOrigins=[]] - Orígenes permitidos para CORP
 * @returns {import('express').RequestHandler[]} Array de middlewares de Helmet
 */
function buildHelmetMiddleware({ isApiOnly = true, allowedOrigins = [] } = {}) {
  return helmet({

    // ── Content-Security-Policy ──────────────────────────────────────────────
    // OWASP A03: Previene XSS al declarar fuentes de contenido válidas.
    // Para una API REST pura, bloqueamos TODO: no debe haber scripts, estilos
    // ni frames. Esto convierte cualquier respuesta HTML accidental en inofensiva.
    contentSecurityPolicy: isApiOnly
      ? {
          directives: {
            defaultSrc: ["'none'"],    // Bloquea TODAS las fuentes por defecto
            scriptSrc:  ["'none'"],    // No permite scripts (es una API, no web)
            styleSrc:   ["'none'"],    // No permite estilos externos
            imgSrc:     ["'none'"],    // No permite imágenes externas
            connectSrc: ["'none'"],    // No permite fetch/XHR desde el navegador
            fontSrc:    ["'none'"],
            objectSrc:  ["'none'"],    // Bloquea Flash, plugins, etc.
            mediaSrc:   ["'none'"],
            frameSrc:   ["'none'"],    // OWASP: previene clickjacking
            formAction: ["'none'"],    // Previene envío de formularios a externos
            baseUri:    ["'none'"],    // Previene ataques de base tag injection
            upgradeInsecureRequests: [], // Fuerza HTTPS en recursos embebidos
          },
        }
      : {
          // Para endpoints con UI de documentación (Swagger), usar configuración menos estricta
          useDefaults: true,
        },

    // ── Cross-Origin-Embedder-Policy ─────────────────────────────────────────
    // Requiere que todos los recursos cross-origin tengan CORS o CORP header.
    // Necesario para habilitar SharedArrayBuffer y características avanzadas.
    crossOriginEmbedderPolicy: { policy: 'require-corp' },

    // ── Cross-Origin-Opener-Policy ───────────────────────────────────────────
    // Aísla el contexto de navegación del origen. Previene Spectre attacks.
    crossOriginOpenerPolicy: { policy: 'same-origin' },

    // ── Cross-Origin-Resource-Policy ─────────────────────────────────────────
    // Solo permite que el mismo origen use los recursos de esta API.
    // Previene ataques de cross-origin reads (CORS de forma más estricta).
    crossOriginResourcePolicy: { policy: 'same-origin' },

    // ── HTTP Strict Transport Security (HSTS) ────────────────────────────────
    // OWASP A02: Fuerza al navegador a usar HTTPS durante 1 año.
    // maxAge: 31536000 = 365 días (mínimo recomendado para preload list)
    // includeSubDomains: aplica a todos los subdominios
    // preload: permite envío a la lista HSTS preload de Chrome/Firefox
    strictTransportSecurity: {
      maxAge: 31_536_000,           // 1 año en segundos
      includeSubDomains: true,
      preload: true,
    },

    // ── X-Content-Type-Options ───────────────────────────────────────────────
    // OWASP A03: Previene MIME type sniffing.
    // Sin este header, IE/Edge podían ejecutar un .txt como JavaScript si
    // el contenido parecía código. 'nosniff' desactiva ese comportamiento.
    xContentTypeOptions: true,       // Agrega: X-Content-Type-Options: nosniff

    // ── X-Frame-Options ──────────────────────────────────────────────────────
    // OWASP A05: Previene clickjacking.
    // 'DENY' evita que la respuesta se muestre dentro de un <iframe>.
    // Aunque CSP ya tiene frameSrc: none, este header mantiene compatibilidad
    // con navegadores antiguos que no soportan CSP.
    xFrameOptions: { action: 'deny' },

    // ── X-XSS-Protection ─────────────────────────────────────────────────────
    // Header legacy para IE/Chrome antiguo. Deshabilitado intencionalmente:
    // en navegadores modernos puede crear vulnerabilidades de bypass XSS.
    // CSP es la defensa moderna y suficiente contra XSS.
    xXssProtection: false,

    // ── Referrer-Policy ──────────────────────────────────────────────────────
    // Controla qué información de referencia se envía en solicitudes cross-origin.
    // 'no-referrer': No envía ningún header Referer. Protege URLs internas
    // del backend (que podrían contener tokens o paths sensibles) de ser
    // enviadas a servicios externos.
    referrerPolicy: { policy: 'no-referrer' },

    // ── Permissions-Policy ───────────────────────────────────────────────────
    // Deshabilita acceso a APIs de hardware del navegador desde esta respuesta.
    // Para una API REST, esto es puramente preventivo.
    permissionsPolicy: {
      features: {
        camera:          [],   // Deshabilita acceso a cámara
        microphone:      [],   // Deshabilita acceso a micrófono
        geolocation:     [],   // Deshabilita geolocalización
        payment:         [],   // Deshabilita Payment Request API
        usb:             [],   // Deshabilita WebUSB
        accelerometer:   [],
        gyroscope:       [],
      },
    },

    // ── X-Powered-By ─────────────────────────────────────────────────────────
    // Helmet elimina automáticamente el header 'X-Powered-By: Express'.
    // OWASP A05: No revelar la tecnología del servidor facilita ataques dirigidos.
    // Helmet lo deshabilita por defecto (hidePoweredBy: true implícito).

    // ── X-DNS-Prefetch-Control ───────────────────────────────────────────────
    // Deshabilita el prefetch de DNS del navegador para URLs en la respuesta.
    // Reduce fugas de información sobre recursos internos de la API.
    dnsPrefetchControl: { allow: false },

    // ── Origin-Agent-Cluster ─────────────────────────────────────────────────
    // Aísla el proceso del agente por origen. Mitiga Spectre side-channel attacks.
    originAgentCluster: true,

  });
}

/**
 * Middleware adicional: Cabeceras de seguridad personalizadas no cubiertas por Helmet.
 * Se aplica DESPUÉS de Helmet en la cadena.
 *
 * @returns {import('express').RequestHandler}
 */
function additionalSecurityHeaders() {
  return (_req, res, next) => {
    // Cache-Control: Previene que proxies intermedios cacheen respuestas de API.
    // Las respuestas de API contienen datos sensibles y dinámicos — nunca deben
    // ser servidas desde caché por un proxy compartido.
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');      // Compatibilidad HTTP/1.0
    res.setHeader('Expires', '0');             // Expira inmediatamente

    // Surrogate-Control: Instrucción explícita para CDNs (Cloudflare, etc.)
    res.setHeader('Surrogate-Control', 'no-store');

    // X-Request-ID: Agrega ID único por request para correlación de logs.
    // Si Railway/proxy inyecta X-Request-ID, lo preservamos; si no, generamos uno.
    if (!res.getHeader('X-Request-ID')) {
      const requestId = `req_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
      res.setHeader('X-Request-ID', requestId);
    }

    next();
  };
}

module.exports = { buildHelmetMiddleware, additionalSecurityHeaders };
