/**
 * @file packages_shared/security/jwtVerify.js
 * @description Middleware de verificación JWT compartido entre microservicios.
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OWASP A07:2021 — Identification and Authentication Failures        ║
 * ║  • Rechaza algoritmo 'none' con whitelist explícita de algoritmos   ║
 * ║  • Verifica claims obligatorios (sub, jti) tras la firma            ║
 * ║  • Consulta blacklist Redis para tokens revocados (post-logout)     ║
 * ║  • Comparación timing-safe para secrets M2M (previene timing attack)║
 * ╚══════════════════════════════════════════════════════════════════════╝
 */

'use strict';

const jwt      = require('jsonwebtoken');
const { timingSafeEqual } = require('crypto');
const { createServiceLogger } = require('./logger');

const logger = createServiceLogger('jwt-verify');

// ── Validación temprana del secret ──────────────────────────────────────────
// Ejecutada al momento de cargar el módulo (no en cada request).
// Si falla, el proceso muere antes de servir cualquier request inseguro.
const JWT_SECRET    = process.env.JWT_SECRET;
const JWT_ALGORITHM = process.env.JWT_ALGORITHM || 'HS512';

// ── A04-1: verificación ASIMÉTRICA (RS256/EdDSA) con CONVIVENCIA ──────────────
// Durante la migración este verificador acepta tokens firmados con la CLAVE
// PÚBLICA nueva (asimétrico) Y con el SECRETO simétrico viejo (HS*), hasta que
// los tokens antiguos expiren de forma natural. auth-service firma con la clave
// privada; el resto de servicios solo necesitan la clave PÚBLICA (distribuible
// sin riesgo). Las claves pueden venir en PEM directo o en base64 (recomendado
// en variables de entorno para evitar problemas con saltos de línea).
function decodeKey(v) {
  if (!v) return null;
  return v.includes('BEGIN') ? v : Buffer.from(v, 'base64').toString('utf8');
}
const JWT_PUBLIC_KEY = decodeKey(process.env.JWT_PUBLIC_KEY);
const JWT_VERIFY_ALGORITHMS = (process.env.JWT_VERIFY_ALGORITHMS || 'RS256')
  .split(',').map((a) => a.trim()).filter(Boolean);

const hasSymmetric  = !!JWT_SECRET && JWT_SECRET.length >= 64;
const hasAsymmetric = !!JWT_PUBLIC_KEY;

if (!hasSymmetric && !hasAsymmetric) {
  logger.error('Config JWT inválida: se requiere JWT_SECRET (≥64) o JWT_PUBLIC_KEY. Proceso terminado.', {
    event:          'SECURITY_CONFIG_FAILURE',
    recommendation: 'Simétrico: 64 bytes hex. Asimétrico: par RS256/EdDSA (auth firma, resto verifica con la pública).',
  });
  process.exit(1);
}

/**
 * Verifica el token probando primero la firma ASIMÉTRICA (clave pública) y, si
 * falla, la SIMÉTRICA (secreto viejo) durante la convivencia. Cada intento FIJA
 * su algoritmo+clave, por lo que NO hay riesgo de confusión de algoritmo (un
 * token HS firmado con la clave pública como secreto no valida contra RS256 con
 * la pública, ni contra HS512 con JWT_SECRET).
 * @param {string} token
 * @returns {object} claims decodificados
 * @throws el último error de verificación si ninguna vía valida.
 */
function verifyToken(token) {
  let lastErr;
  if (hasAsymmetric) {
    try {
      return jwt.verify(token, JWT_PUBLIC_KEY, { algorithms: JWT_VERIFY_ALGORITHMS, complete: false });
    } catch (e) { lastErr = e; }
  }
  if (hasSymmetric) {
    try {
      return jwt.verify(token, JWT_SECRET, { algorithms: [JWT_ALGORITHM], complete: false });
    } catch (e) { lastErr = e; }
  }
  throw lastErr;
}

// ─────────────────────────────────────────────────────────────────────────────
// MIDDLEWARE PRINCIPAL: Verificación de Bearer JWT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @typedef {object} JwtVerifyOptions
 * @property {import('ioredis').Redis|null} [redisClient]   - Para consultar blacklist de JTIs
 * @property {string[]}                    [requiredRoles]  - Roles autorizados ([] = cualquier rol)
 * @property {boolean}                     [optional]       - Si true, no falla si no hay token
 */

/**
 * Crea el middleware de verificación de JWT.
 * Inyecta `req.user` con los claims del token verificado.
 *
 * @param {JwtVerifyOptions} [opts]
 * @returns {import('express').RequestHandler}
 */
function createJwtVerifyMiddleware(opts = {}) {
  const {
    redisClient   = null,
    requiredRoles = [],
    optional      = false,
  } = opts;

  return async (req, res, next) => {
    try {
      const authHeader = req.headers['authorization'];

      // ── Sin header ────────────────────────────────────────────────────────
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        if (optional) return next();          // Rutas opcionales (ej: perfil público)
        return res.status(401).json({
          success: false, data: null,
          error: 'Se requiere autenticación. Formato: Authorization: Bearer <token>',
        });
      }

      const token = authHeader.slice(7).trim();
      if (!token) {
        return res.status(401).json({
          success: false, data: null, error: 'Token de autenticación vacío.',
        });
      }

      // ── Verificar firma y expiración ──────────────────────────────────────
      // verifyToken: asimétrico (clave pública) con fallback simétrico durante la
      // convivencia. algorithms fijados por vía → rechaza alg:none y confusión RS/HS.
      const decoded = verifyToken(token);

      // ── Validar claims de negocio ─────────────────────────────────────────
      if (!decoded.sub || !decoded.jti) {
        logger.warn('JWT sin claims obligatorios (sub, jti)', {
          event: 'JWT_MISSING_CLAIMS',
          hasSub: !!decoded.sub,
          hasJti: !!decoded.jti,
          path:   req.path,
        });
        return res.status(401).json({
          success: false, data: null, error: 'Token de autenticación inválido.',
        });
      }

      // ── Consultar blacklist (tokens revocados por logout/compromiso) ───────
      // OWASP A07: Sin esta verificación, tokens de cuentas eliminadas o
      // comprometidas siguen siendo válidos hasta su expiración natural.
      if (redisClient) {
        const isRevoked = await redisClient.get(`jwt:blacklist:${decoded.jti}`);
        if (isRevoked) {
          logger.warn('Uso de token revocado (blacklist hit)', {
            event:  'JWT_BLACKLISTED',
            jti:    decoded.jti,
            userId: decoded.sub,
          });
          return res.status(401).json({
            success: false, data: null,
            error: 'La sesión ha sido cerrada. Por favor inicia sesión nuevamente.',
          });
        }
      }

      // ── Verificar rol requerido ───────────────────────────────────────────
      if (requiredRoles.length > 0 && !requiredRoles.includes(decoded.role)) {
        logger.warn('Acceso denegado por rol insuficiente', {
          event:         'INSUFFICIENT_ROLE',
          userId:        decoded.sub,
          userRole:      decoded.role,
          requiredRoles,
          path:          req.path,
        });
        return res.status(403).json({
          success: false, data: null,
          error: 'No tienes permisos para acceder a este recurso.',
        });
      }

      // ── Inyectar usuario en el request ────────────────────────────────────
      // Los siguientes middlewares y controllers acceden a req.user
      req.user = {
        id:    decoded.sub,
        email: decoded.email,
        role:  decoded.role,
        jti:   decoded.jti,    // Necesario para revocar en logout
        exp:   decoded.exp,    // exp VERIFICADO → TTL del blacklist sin re-decodificar
      };

      next();

    } catch (err) {
      // JsonWebTokenError, TokenExpiredError → manejado por errorHandler centralizado
      next(err);
    }
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MIDDLEWARE M2M: Autenticación entre microservicios
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Verifica el header `x-inter-service-secret` para llamadas internas (M2M).
 * Usa comparación a tiempo constante para prevenir timing attacks.
 *
 * OWASP A02: timingSafeEqual evita que un atacante deduzca el secret
 * midiendo diferencias de microsegundos en la respuesta.
 *
 * @returns {import('express').RequestHandler}
 */
function createInterServiceAuthMiddleware() {
  const INTER_SERVICE_SECRET = process.env.INTER_SERVICE_SECRET;

  if (!INTER_SERVICE_SECRET || INTER_SERVICE_SECRET.length < 32) {
    logger.error('INTER_SERVICE_SECRET faltante o corto (mín. 32 chars). Proceso terminado.');
    process.exit(1);
  }

  // Pre-calcular el buffer del secret una vez (no en cada request)
  const expectedBuf = Buffer.from(INTER_SERVICE_SECRET, 'utf8');

  return (req, res, next) => {
    const providedSecret = req.headers['x-inter-service-secret'] || '';
    const providedBuf    = Buffer.from(providedSecret, 'utf8');

    // timingSafeEqual requiere buffers del mismo largo → verificar primero
    const match = providedBuf.length === expectedBuf.length
      && timingSafeEqual(providedBuf, expectedBuf);

    if (!match) {
      logger.warn('Autenticación M2M fallida', {
        event:    'INTER_SERVICE_AUTH_FAILED',
        caller:   req.headers['x-service-name'] || 'unknown',
        path:     req.path,
        ip:       req.ip,
      });
      return res.status(401).json({
        success: false, data: null, error: 'Acceso no autorizado.',
      });
    }

    next();
  };
}

module.exports = { createJwtVerifyMiddleware, createInterServiceAuthMiddleware };
