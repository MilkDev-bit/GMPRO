/**
 * @file services/auth-service/src/middlewares/jwtVerify.js
 * @description Middleware de verificación de JWT para rutas protegidas.
 *
 * OWASP A07:2021 — Identification and Authentication Failures:
 *   • Verifica firma, expiración y claims obligatorios del token
 *   • Comprueba que el token no haya sido revocado (blacklist en Redis)
 *   • Rechaza algoritmo 'none' (vulnerabilidad clásica de JWT)
 */

'use strict';

const jwt = require('jsonwebtoken');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('jwt-verify');

const JWT_SECRET    = process.env.JWT_SECRET;
const JWT_ALGORITHM = process.env.JWT_ALGORITHM || 'HS512';

// Validación temprana: falla el proceso si JWT_SECRET no está configurado
if (!JWT_SECRET || JWT_SECRET.length < 64) {
  logger.error('JWT_SECRET no configurado o demasiado corto (mínimo 64 caracteres). Proceso terminado.', {
    event: 'SECURITY_CONFIG_FAILURE',
    recommendation: 'Generar con: node -e "console.log(require(\'crypto\').randomBytes(64).toString(\'hex\'))"',
  });
  process.exit(1);
}

/**
 * Crea el middleware de verificación JWT.
 *
 * @param {object} [options]
 * @param {import('ioredis').Redis|null} [options.redisClient] - Para verificar blacklist
 * @param {string[]} [options.requiredRoles=[]]               - Roles autorizados (ej: ['admin'])
 * @returns {import('express').RequestHandler}
 */
function createJwtVerifyMiddleware({ redisClient = null, requiredRoles = [] } = {}) {
  return async (req, res, next) => {
    try {
      // ─── Extraer token del header Authorization ──────────────────────────
      const authHeader = req.headers['authorization'];

      if (!authHeader) {
        return res.status(401).json({
          success: false,
          data: null,
          error: 'Se requiere autenticación.',
        });
      }

      // Formato esperado: "Bearer <token>"
      if (!authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
          success: false,
          data: null,
          error: 'Formato de token inválido. Use: Authorization: Bearer <token>',
        });
      }

      const token = authHeader.slice(7).trim(); // Eliminar "Bearer "

      if (!token) {
        return res.status(401).json({
          success: false,
          data: null,
          error: 'Token de autenticación vacío.',
        });
      }

      // ─── Verificar firma y claims del JWT ────────────────────────────────
      // jwt.verify lanza excepción si:
      //   - La firma no es válida (manipulación del token)
      //   - El token ha expirado (exp claim)
      //   - El algoritmo no coincide (previene ataque 'alg:none')
      const decoded = jwt.verify(token, JWT_SECRET, {
        algorithms: [JWT_ALGORITHM], // Lista blanca de algoritmos — rechaza 'none'
        complete: false,             // Solo retorna payload (no header+payload)
      });

      // ─── Verificar claims obligatorios ───────────────────────────────────
      // Defensivo: aunque jwt.verify ya verifica exp e iat, validamos explícitamente
      // los campos de negocio que deben estar presentes.
      if (!decoded.sub || !decoded.jti) {
        logger.warn('Token JWT sin claims obligatorios (sub, jti)', {
          event: 'JWT_MISSING_CLAIMS',
          hasSub: !!decoded.sub,
          hasJti: !!decoded.jti,
        });
        return res.status(401).json({
          success: false,
          data: null,
          error: 'Token de autenticación inválido.',
        });
      }

      // ─── Verificar blacklist (tokens revocados) ───────────────────────────
      // Cuando un usuario hace logout, el JTI del token se agrega a la blacklist
      // en Redis con TTL = tiempo restante de vida del token.
      // OWASP A07: Sin blacklist, un token de un usuario eliminado/bloqueado
      // seguiría siendo válido hasta su expiración natural.
      if (redisClient) {
        const blacklistKey = `jwt:blacklist:${decoded.jti}`;
        const isBlacklisted = await redisClient.get(blacklistKey);

        if (isBlacklisted) {
          logger.warn('Intento de uso de token revocado', {
            event: 'JWT_BLACKLISTED',
            jti: decoded.jti,
            userId: decoded.sub,
          });
          return res.status(401).json({
            success: false,
            data: null,
            error: 'La sesión ha sido cerrada. Por favor, inicia sesión nuevamente.',
          });
        }
      }

      // ─── Verificar rol (si se requiere) ──────────────────────────────────
      if (requiredRoles.length > 0) {
        const userRole = decoded.role;
        if (!requiredRoles.includes(userRole)) {
          logger.warn('Acceso denegado por rol insuficiente', {
            event: 'INSUFFICIENT_ROLE',
            userId: decoded.sub,
            userRole,
            requiredRoles,
            path: req.path,
          });
          return res.status(403).json({
            success: false,
            data: null,
            error: 'No tienes permisos para acceder a este recurso.',
          });
        }
      }

      // ─── Inyectar usuario en el request ──────────────────────────────────
      // Los middlewares y controllers posteriores acceden al usuario vía req.user
      req.user = {
        id:    decoded.sub,    // UUID del usuario (auth_service_db.usuarios.id)
        email: decoded.email,
        role:  decoded.role,
        jti:   decoded.jti,   // Necesario para logout/blacklist
      };

      // Propagar request ID si está en el token (para correlación de logs)
      if (decoded.requestId) {
        req.correlationId = decoded.requestId;
      }

      next();

    } catch (err) {
      // Dejar que el errorHandler centralizado maneje errores JWT (JsonWebTokenError, etc.)
      next(err);
    }
  };
}

/**
 * Middleware que verifica el INTER_SERVICE_SECRET para llamadas M2M.
 * Usado cuando access-service o ai-service llaman a auth-service internamente.
 *
 * @returns {import('express').RequestHandler}
 */
function createInterServiceAuthMiddleware() {
  const INTER_SERVICE_SECRET = process.env.INTER_SERVICE_SECRET;

  if (!INTER_SERVICE_SECRET || INTER_SERVICE_SECRET.length < 32) {
    logger.error('INTER_SERVICE_SECRET no configurado o demasiado corto. Proceso terminado.');
    process.exit(1);
  }

  return (req, res, next) => {
    const serviceSecret = req.headers['x-inter-service-secret'];

    // Comparación a tiempo constante para prevenir timing attacks
    // OWASP A02: Un atacante puede medir el tiempo de respuesta para deducir
    // qué parte del secret coincide. crypto.timingSafeEqual previene esto.
    const { timingSafeEqual } = require('crypto');
    const provided = Buffer.from(serviceSecret || '', 'utf8');
    const expected = Buffer.from(INTER_SERVICE_SECRET, 'utf8');

    const secretsMatch = provided.length === expected.length
      && timingSafeEqual(provided, expected);

    if (!secretsMatch) {
      logger.warn('Intento de acceso M2M con secret inválido', {
        event: 'INTER_SERVICE_AUTH_FAILED',
        path: req.path,
        ip: req.ip,
        callerHeader: req.headers['x-service-name'] || 'unknown',
      });
      return res.status(401).json({
        success: false,
        data: null,
        error: 'Acceso no autorizado.',
      });
    }

    next();
  };
}

module.exports = { createJwtVerifyMiddleware, createInterServiceAuthMiddleware };
