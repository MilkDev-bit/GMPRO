/**
 * @file services/auth-service/src/middlewares/inputSanitizer.js
 * @description Sanitización defensiva de entradas de texto (anti stored-XSS) para
 * campos de perfil y DATOS MÉDICOS (historial_clinico, contacto_emergencia).
 *
 * CONTEXTO DE AMENAZA:
 *   • SQL Injection clásico: NO es explotable a través del cliente de Supabase /
 *     PostgREST porque las queries son parametrizadas (no se concatena SQL). Aun así,
 *     nunca se debe interpolar entrada de usuario en filtros `.or()` sin sanear.
 *   • Stored XSS: el historial_clinico (JSONB libre) y el contacto de emergencia se
 *     guardan tal cual; si el frontend los renderiza sin escapar, un `<script>`
 *     inyectado se ejecutaría. Esta capa neutraliza HTML/JS en el ingreso como
 *     defensa en profundidad (la defensa primaria sigue siendo el output-encoding
 *     en el cliente).
 *
 * Uso (drop-in):
 *   router.post('/perfil', sanitizeFields(['historial_clinico','contacto_emergencia','nombre']), handler)
 */

'use strict';

const MAX_STRING = 5000;
const MAX_DEPTH  = 6;
const MAX_ARRAY  = 200;
const MAX_KEYS   = 100;

/**
 * Neutraliza una cadena: elimina etiquetas HTML, handlers inline, esquemas
 * peligrosos y caracteres de control (conservando \n, \r, \t).
 * @param {string} input
 * @param {number} [max=MAX_STRING]
 * @returns {string}
 */
function sanitizeString(input, max = MAX_STRING) {
  return String(input)
    // Caracteres de control excepto tab(09), LF(0A), CR(0D).
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '')
    // Etiquetas HTML completas (<script>, <img ...>, </div>, etc.).
    .replace(/<\s*\/?\s*[a-zA-Z][^>]*>/g, '')
    // Ángulos residuales que podrían reconstruir markup.
    .replace(/[<>]/g, '')
    // Esquemas y handlers de ejecución.
    .replace(/javascript:/gi, '')
    .replace(/on[a-z]+\s*=/gi, '')
    .slice(0, max);
}

/**
 * Sanea recursivamente strings dentro de objetos/arrays (JSONB médico anidado),
 * con límites de profundidad/tamaño para evitar abuso (DoS por payloads enormes).
 * @param {*} value
 * @param {number} [depth=0]
 * @returns {*}
 */
function sanitizeDeep(value, depth = 0) {
  if (depth > MAX_DEPTH) return null;
  if (typeof value === 'string') return sanitizeString(value);
  if (Array.isArray(value)) {
    return value.slice(0, MAX_ARRAY).map((v) => sanitizeDeep(v, depth + 1));
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).slice(0, MAX_KEYS)) {
      out[sanitizeString(key, 100)] = sanitizeDeep(value[key], depth + 1);
    }
    return out;
  }
  // number, boolean, null, undefined → se devuelven intactos.
  return value;
}

/**
 * Middleware factory: sanea in-place los campos indicados de req.body.
 * @param {string[]} fields
 * @returns {import('express').RequestHandler}
 */
function sanitizeFields(fields) {
  return (req, _res, next) => {
    if (req.body && typeof req.body === 'object') {
      for (const field of fields) {
        if (field in req.body) {
          req.body[field] = sanitizeDeep(req.body[field]);
        }
      }
    }
    next();
  };
}

module.exports = { sanitizeString, sanitizeDeep, sanitizeFields };
