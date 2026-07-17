/**
 * @file services/access-service/src/middlewares/turnstileAuth.js
 * @description Autenticación para hardware de lectoras y torniquetes.
 * Utiliza comparación a tiempo constante (timingSafeEqual) para evitar timing attacks.
 */

'use strict';

const { timingSafeEqual } = require('crypto');
const env                 = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:turnstileAuth');

const MASTER_TURNSTILE_KEY_BUF = Buffer.from(env.TURNSTILE_API_KEY, 'utf8');

function requireTurnstileApiKey(req, res, next) {
  let apiKey = null;

  if (req.headers['x-turnstile-key']) {
    apiKey = req.headers['x-turnstile-key'];
  } else if (req.headers['x-api-key']) {
    apiKey = req.headers['x-api-key'];
  } else if (req.headers['authorization']?.startsWith('ApiKey ')) {
    apiKey = req.headers['authorization'].slice(7).trim();
  }

  if (!apiKey) {
    logger.warn('Intento de acceso desde torniquete sin API Key', {
      path: req.path, ip: req.ip,
    });
    return res.status(401).json({
      success: false, data: null,
      error: 'API Key de torniquete requerida (x-turnstile-key o x-api-key).',
    });
  }

  const providedBuf = Buffer.from(apiKey, 'utf8');
  const keysMatch = providedBuf.length === MASTER_TURNSTILE_KEY_BUF.length
    && timingSafeEqual(providedBuf, MASTER_TURNSTILE_KEY_BUF);

  if (!keysMatch) {
    logger.warn('API Key de torniquete inválida', { path: req.path, ip: req.ip });
    return res.status(401).json({
      success: false, data: null, error: 'API Key de hardware inválida o expirada.',
    });
  }

  // Identificar el ID del torniquete opcionalmente mediante un header secundario
  const turnstileId = req.headers['x-turnstile-id'] || 'turnstile_01';
  req.turnstile = { id: turnstileId };

  next();
}

module.exports = { requireTurnstileApiKey };
