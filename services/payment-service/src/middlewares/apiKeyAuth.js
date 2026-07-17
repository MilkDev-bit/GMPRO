/**
 * @file services/payment-service/src/middlewares/apiKeyAuth.js
 * @description Middleware de autenticación por API Key para el endpoint de pago en efectivo.
 *
 * ¿Por qué API Key y no JWT?
 *   El recepcionista usa la app de administración (panel web o app interna).
 *   En lugar de gestionar usuarios/sesiones separadas, se configura una API Key
 *   estática por recepcionista en el panel de administración.
 *   Cada recepcionista tiene su propio ID codificado en la clave para trazabilidad.
 *
 * Formato de la API Key:
 *   "gympro_cash_{receptionist_id}_{random_hex}"
 *   Ejemplo: "gympro_cash_rec01_a3f9b2c1d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9"
 *
 * Almacenamiento:
 *   Las API Keys se almacenan hasheadas (SHA-256) en la DB de Supabase.
 *   El texto plano solo se muestra UNA vez al crear el recepcionista.
 *
 * OWASP A07: La comparación usa timingSafeEqual para prevenir timing attacks.
 * OWASP A09: Cada uso de la API Key queda registrado en logs.
 *
 * NOTA: Por simplicidad de despliegue inicial, se permite configurar
 *   una API Key maestra en CASH_PAYMENT_API_KEY (variable de entorno).
 *   En producción, migrar a API Keys por recepcionista en la DB.
 */

'use strict';

const { timingSafeEqual } = require('crypto');
const env = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:apiKeyAuth');

// Pre-calcular el buffer de la API Key maestra (se hace UNA vez al cargar el módulo)
const MASTER_API_KEY_BUF = Buffer.from(env.CASH_PAYMENT_API_KEY, 'utf8');

/**
 * Middleware que verifica el header `x-api-key` o `Authorization: ApiKey <key>`.
 * Soporta dos formatos para compatibilidad con diferentes clientes del panel.
 *
 * @param {import('express').Request}  req
 * @param {import('express').Response} res
 * @param {Function}                   next
 */
function requireApiKey(req, res, next) {
  // ── Extraer la API Key del request ─────────────────────────────────────────
  let apiKey = null;

  // Formato 1: Header dedicado (recomendado)
  if (req.headers['x-api-key']) {
    apiKey = req.headers['x-api-key'];
  }
  // Formato 2: Authorization: ApiKey <key> (compatibilidad)
  else if (req.headers['authorization']?.startsWith('ApiKey ')) {
    apiKey = req.headers['authorization'].slice(7).trim();
  }

  if (!apiKey) {
    logger.warn('Intento de acceso a /cash-payment sin API Key', {
      event:  'CASH_PAYMENT_NO_API_KEY',
      path:   req.path,
      ip:     req.ip,
      method: req.method,
    });
    return res.status(401).json({
      success: false, data: null,
      error: 'API Key requerida. Usa el header x-api-key.',
    });
  }

  // ── Comparación a tiempo constante ─────────────────────────────────────────
  // OWASP A02: timingSafeEqual previene que un atacante mida el tiempo de
  // respuesta para adivinar caracteres de la API Key uno a uno.
  const providedBuf = Buffer.from(apiKey, 'utf8');

  // timingSafeEqual requiere buffers del mismo tamaño
  const keysMatch = providedBuf.length === MASTER_API_KEY_BUF.length
    && timingSafeEqual(providedBuf, MASTER_API_KEY_BUF);

  if (!keysMatch) {
    logger.warn('API Key inválida para /cash-payment', {
      event:  'CASH_PAYMENT_INVALID_API_KEY',
      path:   req.path,
      ip:     req.ip,
      // Loguear solo los primeros 8 chars para diagnóstico sin exponer la clave
      keyPrefix: apiKey.substring(0, 8) + '...',
    });
    return res.status(401).json({
      success: false, data: null,
      error: 'API Key inválida o expirada.',
    });
  }

  // ── Extraer ID del recepcionista de la API Key ──────────────────────────────
  // Formato: "gympro_cash_{receptionist_id}_{hex}"
  // Si la clave no sigue el formato, usamos 'sistema' como fallback
  const parts = apiKey.split('_');
  const receptionistaId = parts.length >= 3 ? `${parts[0]}_${parts[1]}_${parts[2]}` : 'sistema';

  // Inyectar el ID del recepcionista en el request para el controller
  req.receptionista = { id: receptionistaId };

  logger.info('API Key válida — acceso a /cash-payment autorizado', {
    event:          'CASH_PAYMENT_API_KEY_VALID',
    receptionistaId,
    ip:             req.ip,
    method:         req.method,
  });

  next();
}

module.exports = { requireApiKey };
