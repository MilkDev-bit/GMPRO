/**
 * @file services/fitness-service/src/utils/postgrestSanitizer.js
 * @description Saneamiento anti-inyección para valores que se interpolan en filtros
 * PostgREST (Supabase), en particular en expresiones `.or('col.ilike.%q%')`.
 *
 * VECTOR MITIGADO: PostgREST usa `,` para separar filtros, `()` para agrupar y
 * `*`/`%` como comodines. Un `q` sin sanear (p. ej. `a,id.eq.1)` ) podría reescribir
 * la lógica del filtro o forzar escaneos. Neutralizamos esos metacaracteres antes
 * de construir la expresión, dejando solo texto de búsqueda seguro.
 */

'use strict';

/**
 * Sanea un término de búsqueda para uso seguro dentro de un filtro ilike de PostgREST.
 * @param {string} raw
 * @param {number} [maxLen=60]
 * @returns {string} término seguro (puede quedar vacío si todo era ruido)
 */
function sanitizeLikeQuery(raw, maxLen = 60) {
  if (typeof raw !== 'string') return '';
  return raw
    .normalize('NFC')
    .replace(/[,()%*:\\"'`]/g, ' ')   // metacaracteres PostgREST / comodines / comillas
    .replace(/[\u0000-\u001f]+/g, ' ') // caracteres de control
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLen)
    .trim();
}

/**
 * Normaliza un código de barras a solo dígitos (defensa ante rutas manipuladas).
 * @param {string} raw
 * @param {number} [maxLen=32]
 * @returns {string}
 */
function sanitizeBarcode(raw, maxLen = 32) {
  return String(raw || '').replace(/\D/g, '').slice(0, maxLen);
}

module.exports = { sanitizeLikeQuery, sanitizeBarcode };
