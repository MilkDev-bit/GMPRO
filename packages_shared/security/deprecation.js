/**
 * @file packages_shared/security/deprecation.js
 * @description Middleware para marcar rutas DEPRECADAS sin romperlas (API9).
 *
 * Estándares:
 *   • `Deprecation: true`  — RFC 8594 (indica que el recurso está deprecado).
 *   • `Sunset: <HTTP-date>` — RFC 8594 (fecha planificada de retiro).
 *   • `Link: <successor>; rel="successor-version"` — RFC 8288 (ruta canónica).
 *
 * Además emite un log de WARNING con `event: DEPRECATED_ROUTE_USED` para que la
 * observabilidad muestre QUÉ clientes siguen usando la ruta vieja antes de
 * retirarla. NO altera el comportamiento (la petición sigue su curso normal).
 */

'use strict';

/**
 * @param {object}  opts
 * @param {object}  [opts.logger]     - logger con .warn (winston). Opcional.
 * @param {string}  opts.successor    - ruta canónica sucesora (ej. '/api/v1/generate-qr').
 * @param {string}  [opts.sunset]     - HTTP-date de retiro (ej. 'Sun, 24 Jan 2027 00:00:00 GMT').
 * @returns {import('express').RequestHandler}
 */
function createDeprecationNotice({ logger = null, successor, sunset } = {}) {
  return (req, res, next) => {
    res.set('Deprecation', 'true');
    if (sunset) res.set('Sunset', sunset);
    if (successor) res.set('Link', `<${successor}>; rel="successor-version"`);

    if (logger && typeof logger.warn === 'function') {
      logger.warn('Ruta deprecada utilizada', {
        event:     'DEPRECATED_ROUTE_USED',
        method:    req.method,
        path:      req.originalUrl,
        successor,
        // No logueamos body ni auth; solo lo necesario para inventariar clientes.
        userAgent: req.headers['user-agent'] || null,
        ip:        req.ip,
      });
    }
    next();
  };
}

module.exports = { createDeprecationNotice };
