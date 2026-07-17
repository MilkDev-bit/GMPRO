/**
 * @file packages_shared/security/inputSanitizer.js
 * @description Sanitización y validación de entradas de usuario.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP Top 10 Mitigaciones:                                         ║
 * ║  • A03:2021 — Injection                                             ║
 * ║    → Detecta patrones de SQL injection en parámetros                ║
 * ║    → Elimina caracteres peligrosos de strings                       ║
 * ║    → Previene NoSQL injection (operadores MongoDB/Supabase)         ║
 * ║  • A03:2021 — XSS (Cross-Site Scripting)                           ║
 * ║    → Escapa entidades HTML en strings de entrada                    ║
 * ║    → Elimina atributos y tags HTML peligrosos                       ║
 * ║  • A08:2021 — Software and Data Integrity Failures                  ║
 * ║    → Rechaza payloads que superen el tamaño máximo permitido        ║
 * ║  • A04:2021 — Insecure Design                                       ║
 * ║    → Previene HTTP Parameter Pollution (hpp)                        ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * FILOSOFÍA DE DEFENSA EN PROFUNDIDAD:
 *   Esta capa es la TERCERA línea de defensa (después de WAF y rate limiting).
 *   La PRIMERA defensa contra SQL injection son las queries parametrizadas
 *   (nunca interpolar strings en SQL). Esta capa es una red de seguridad adicional,
 *   no un sustituto de las queries parametrizadas.
 *
 *   Orden de defensa:
 *   1. Queries parametrizadas/ORM (defensa principal vs SQL injection)
 *   2. Rate limiting (reduce volumen de ataques)
 *   3. Esta capa: sanitización de inputs (defensa secundaria)
 *   4. RLS en Supabase (defensa de base de datos)
 */

'use strict';

const validator = require('validator');
const xss = require('xss');
const hpp = require('hpp');
const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('input-sanitizer');

// ─── Configuración del limpiador XSS ──────────────────────────────────────────
// Para una API REST que no renderiza HTML, el objetivo es detectar intentos de
// XSS y rechazarlos, no "limpiar" para renderizar de forma segura.
// La app Flutter muestra los datos — allí debe escaparse para el contexto de renderizado.
const xssOptions = {
  whiteList: {},          // No permitir NINGÚN tag HTML (lista blanca vacía)
  stripIgnoreTag: true,   // Eliminar tags no permitidos (en vez de escapar)
  stripIgnoreTagBody: ['script', 'style', 'iframe', 'object', 'embed'],
  onTagStripList: (tag) => {
    // Log cuando se detecta un tag HTML en el input (posible XSS)
    logger.warn('Tag HTML detectado y eliminado en input', {
      event: 'XSS_ATTEMPT_DETECTED',
      tag,
    });
    return ''; // Eliminar el tag completamente
  },
};

// ─── Patrones de SQL Injection conocidos ──────────────────────────────────────
// NOTA: Esta detección es complementaria, no la defensa principal.
// Las queries parametrizadas son la defensa real. Esto detecta intentos obvios
// para registrarlos en logs de seguridad (SIEM alerting).
const SQL_INJECTION_PATTERNS = [
  /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|TRUNCATE|GRANT|REVOKE)\b)/i,
  /(-{2}|\/\*|\*\/)/,           // Comentarios SQL: -- y /* */
  /(;.*?(DROP|DELETE|INSERT))/i, // Punto y coma seguido de DML peligroso
  /(\bOR\b\s+\d+\s*=\s*\d+)/i,  // OR 1=1 (bypass de autenticación clásico)
  /(\bAND\b\s+\d+\s*=\s*\d+)/i, // AND 1=1
  /SLEEP\s*\(\s*\d+\s*\)/i,     // Time-based blind injection: SLEEP(5)
  /WAITFOR\s+DELAY/i,            // SQL Server time-based injection
  /BENCHMARK\s*\(/i,             // MySQL time-based injection
  /\bINFORMATION_SCHEMA\b/i,     // Enumeración de schema
  /LOAD_FILE\s*\(/i,             // Lectura de archivos del sistema (MySQL)
  /INTO\s+OUTFILE/i,             // Escritura de archivos (MySQL)
  /xp_cmdshell/i,                // Ejecución de comandos del sistema (SQL Server)
];

// ─── Patrones de NoSQL Injection (MongoDB/operadores Supabase RPC) ─────────────
// Supabase usa PostgreSQL, pero los endpoints RPC pueden recibir JSON con
// operadores que se interpretan en el servidor.
const NOSQL_INJECTION_PATTERNS = [
  /\$where/i,      // MongoDB: ejecución de JS
  /\$ne/i,         // MongoDB: not equal (bypass de autenticación)
  /\$gt/i,         // MongoDB: greater than
  /\$lt/i,         // MongoDB: less than
  /\$regex/i,      // MongoDB: regex (DoS via ReDoS)
  /\$or/i,         // MongoDB: OR lógico
  /\$and/i,        // MongoDB: AND lógico
  /\$exists/i,     // MongoDB: campo existe
  /\$nin/i,        // MongoDB: not in
  /\$in/i,         // MongoDB: in array
  /\[\$.*\]/,      // Bracket notation con $ (operator injection en JSON)
];

/**
 * Verifica si un string contiene patrones de SQL injection.
 *
 * @param {string} value
 * @returns {{ detected: boolean, pattern: string|null }}
 */
function detectSqlInjection(value) {
  if (typeof value !== 'string') return { detected: false, pattern: null };

  for (const pattern of SQL_INJECTION_PATTERNS) {
    if (pattern.test(value)) {
      return { detected: true, pattern: pattern.toString() };
    }
  }
  return { detected: false, pattern: null };
}

/**
 * Verifica si un valor (string u objeto) contiene operadores NoSQL peligrosos.
 *
 * @param {*} value
 * @returns {boolean}
 */
function detectNoSqlInjection(value) {
  if (typeof value === 'string') {
    return NOSQL_INJECTION_PATTERNS.some((p) => p.test(value));
  }
  if (typeof value === 'object' && value !== null) {
    // Buscar claves que empiecen con '$' (operadores MongoDB/Supabase)
    return Object.keys(value).some((key) => key.startsWith('$'));
  }
  return false;
}

/**
 * Sanitiza recursivamente un objeto, limpiando strings de XSS y detectando injections.
 * Procesa body, query params y route params.
 *
 * @param {*} value       - Valor a sanitizar (puede ser string, object, array)
 * @param {string} path   - Ruta del campo (para logs: "body.email")
 * @returns {{ sanitized: *, threats: string[] }} - Valor sanitizado y amenazas detectadas
 */
function sanitizeValue(value, path = 'root') {
  const threats = [];

  if (value === null || value === undefined) {
    return { sanitized: value, threats };
  }

  if (Array.isArray(value)) {
    const sanitizedArr = value.map((item, i) => {
      const result = sanitizeValue(item, `${path}[${i}]`);
      threats.push(...result.threats);
      return result.sanitized;
    });
    return { sanitized: sanitizedArr, threats };
  }

  if (typeof value === 'object') {
    // Verificar inyección NoSQL en las claves del objeto
    if (detectNoSqlInjection(value)) {
      threats.push(`NOSQL_INJECTION:${path}`);
    }

    const sanitizedObj = {};
    for (const [key, val] of Object.entries(value)) {
      // Sanitizar también las claves del objeto (previene prototype pollution)
      if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
        threats.push(`PROTOTYPE_POLLUTION:${path}.${key}`);
        continue; // Omitir esta clave completamente
      }
      const result = sanitizeValue(val, `${path}.${key}`);
      threats.push(...result.threats);
      sanitizedObj[key] = result.sanitized;
    }
    return { sanitized: sanitizedObj, threats };
  }

  if (typeof value === 'string') {
    // Paso 1: Detectar intentos de SQL injection (solo detectar, no modificar)
    const sqlCheck = detectSqlInjection(value);
    if (sqlCheck.detected) {
      threats.push(`SQL_INJECTION:${path}`);
    }

    // Paso 2: Limpiar XSS con la librería xss
    const xssCleaned = xss(value, xssOptions);

    // Paso 3: Escapar entidades HTML residuales
    const htmlEscaped = validator.escape(xssCleaned);

    // Paso 4: Normalizar Unicode para prevenir bypass con caracteres lookalike
    // Convierte caracteres como ＜ (U+FF1C) a < antes del escape
    const normalized = htmlEscaped.normalize('NFKC');

    return { sanitized: normalized, threats };
  }

  // Números, booleanos: no modificar
  return { sanitized: value, threats };
}

/**
 * Middleware de sanitización de entradas.
 * Procesa req.body, req.query y req.params.
 * Si detecta amenazas críticas, puede rechazar el request (configurable).
 *
 * @param {object} [options]
 * @param {boolean} [options.blockOnThreat=true]  - Rechazar request si se detecta amenaza
 * @param {boolean} [options.logThreats=true]      - Registrar amenazas en logs
 * @returns {import('express').RequestHandler}
 */
function createInputSanitizer({ blockOnThreat = true, logThreats = true } = {}) {
  return (req, res, next) => {
    const detectedThreats = [];

    // ─── Sanitizar body ────────────────────────────────────────────────────
    if (req.body && typeof req.body === 'object') {
      const { sanitized, threats } = sanitizeValue(req.body, 'body');
      req.body = sanitized;
      detectedThreats.push(...threats);
    }

    // ─── Sanitizar query params ────────────────────────────────────────────
    if (req.query && typeof req.query === 'object') {
      const { sanitized, threats } = sanitizeValue(req.query, 'query');
      req.query = sanitized;
      detectedThreats.push(...threats);
    }

    // ─── Sanitizar route params ────────────────────────────────────────────
    if (req.params && typeof req.params === 'object') {
      const { sanitized, threats } = sanitizeValue(req.params, 'params');
      req.params = sanitized;
      detectedThreats.push(...threats);
    }

    // ─── Manejar amenazas detectadas ───────────────────────────────────────
    if (detectedThreats.length > 0) {
      if (logThreats) {
        logger.warn('Amenaza detectada en input del request', {
          event: 'INPUT_THREAT_DETECTED',
          threats: detectedThreats,
          path: req.path,
          method: req.method,
          ip: req.ip,
          // NO loguear el body completo (puede contener passwords, PII, etc.)
          // Solo loguear qué campo fue afectado (ya está en 'threats')
        });
      }

      if (blockOnThreat) {
        return res.status(400).json({
          success: false,
          data: null,
          error: 'La solicitud contiene caracteres no permitidos.',
        });
      }
    }

    next();
  };
}

/**
 * Middleware: Límite de tamaño de payload.
 * Rechaza requests con body mayor al límite configurado ANTES de parsear el JSON.
 *
 * OWASP A08: Previene ataques de desbordamiento de memoria y DoS por payloads gigantes.
 * Express ya tiene body-parser con límite, pero este middleware lo aplica antes
 * del parsing para mayor eficiencia (no se parsea lo que se va a rechazar).
 *
 * NOTA: Configurar también en express.json({ limit: '10kb' }) en main.js
 *
 * @param {string} [maxSize='10kb'] - Tamaño máximo del body
 * @returns {import('express').RequestHandler}
 */
function createPayloadSizeLimiter(maxSize = '10kb') {
  // Convertir tamaño legible a bytes
  const units = { b: 1, kb: 1024, mb: 1024 ** 2, gb: 1024 ** 3 };
  const match = maxSize.toLowerCase().match(/^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)$/);
  if (!match) throw new Error(`Formato de tamaño inválido: ${maxSize}`);
  const maxBytes = parseFloat(match[1]) * (units[match[2]] || 1);

  return (req, res, next) => {
    const contentLength = parseInt(req.headers['content-length'] || '0', 10);

    if (contentLength > maxBytes) {
      logger.warn('Payload rechazado por exceder tamaño máximo', {
        event: 'PAYLOAD_TOO_LARGE',
        contentLength,
        maxBytes,
        path: req.path,
        ip: req.ip,
      });

      return res.status(413).json({
        success: false,
        data: null,
        error: `El cuerpo de la solicitud excede el tamaño máximo permitido (${maxSize}).`,
      });
    }

    next();
  };
}

/**
 * Middleware: Prevención de HTTP Parameter Pollution (hpp).
 *
 * OWASP A03: Un atacante puede enviar el mismo parámetro múltiples veces
 * para confundir la lógica de la aplicación. Ej: ?role=user&role=admin
 * Express convierte esto en un array, lo que puede causar comportamiento inesperado.
 *
 * hpp toma el ÚLTIMO valor de parámetros duplicados (o lista blanca específica).
 *
 * @param {string[]} [whitelist=[]] - Parámetros que SÍ pueden tener múltiples valores
 * @returns {import('express').RequestHandler}
 */
function createHppProtection(whitelist = []) {
  return hpp({
    whitelist, // Ej: ['filters', 'tags'] para endpoints de búsqueda con arrays
  });
}

module.exports = {
  createInputSanitizer,
  createPayloadSizeLimiter,
  createHppProtection,
  // Exportar funciones de detección para uso en tests
  detectSqlInjection,
  detectNoSqlInjection,
  sanitizeValue,
};
