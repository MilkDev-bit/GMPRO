/**
 * @file services/access-service/src/middlewares/interServiceAuth.js
 * @description Autenticación servicio-a-servicio (payment-service → access-service)
 * para endpoints internos de sincronización (invalidar caché, acuñar cortesía).
 *
 * Usa el secreto compartido INTER_SERVICE_SECRET (mismo valor en ambos servicios)
 * comparado a tiempo constante (timingSafeEqual) para evitar timing attacks (OWASP A02).
 * Estos endpoints NUNCA se exponen al público: solo tráfico interno de la red de Railway.
 */

'use strict';

const { timingSafeEqual }     = require('crypto');
const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:interServiceAuth');

const SECRET_BUF = Buffer.from(env.INTER_SERVICE_SECRET, 'utf8');

function requireInterServiceSecret(req, res, next) {
  const provided = req.headers['x-inter-service-secret'];

  if (!provided) {
    logger.warn('Endpoint interno invocado sin x-inter-service-secret', {
      path: req.path, ip: req.ip,
    });
    return res.status(401).json({
      success: false, data: null,
      error: 'Secreto inter-servicio requerido (x-inter-service-secret).',
    });
  }

  const providedBuf = Buffer.from(provided, 'utf8');
  const match = providedBuf.length === SECRET_BUF.length
    && timingSafeEqual(providedBuf, SECRET_BUF);

  if (!match) {
    logger.warn('Secreto inter-servicio inválido en endpoint interno', {
      path: req.path, ip: req.ip,
    });
    return res.status(403).json({
      success: false, data: null, error: 'Secreto inter-servicio inválido.',
    });
  }

  next();
}

module.exports = { requireInterServiceSecret };
