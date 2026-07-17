/**
 * @file services/access-service/src/controllers/qrController.js
 * @description Controladores para generación de código QR dinámico y validación en torniquete.
 *
 * CUMPLE CON TAREA 3.2:
 *   • Recibe usuario_id desde el JWT del cliente.
 *   • Consulta vigencia de membresía en payment-service (estado 'active'/'free_pass', valido_hasta > now).
 *   • Genera token AES-256 con usuario_id, timestamp actual y nonce de un solo uso (30s TTL).
 *   • Retorna 402 Payment Required si está vencido o con adeudos.
 */

'use strict';

const cryptoService        = require('../services/cryptoService');
const paymentClientService = require('../services/paymentClientService');
const accessModel          = require('../models/accessModel');
const env                  = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:qrController');

// ── GET /api/v1/qr/generate ───────────────────────────────────────────────────
// (También disponible en /api/v1/generate-qr según especificación de tarea)
/**
 * Genera un código QR dinámico y efímero para el usuario autenticado.
 * Requiere JWT (inyecta req.user).
 */
async function generateQr(req, res, next) {
  try {
    const usuarioId = req.user.id;

    // 1. Verificar si el usuario cuenta con membresía activa en payment-service / DB
    const membership = await paymentClientService.checkMembershipValidity(usuarioId, req.redisClient);

    if (!membership.valid) {
      logger.warn('Intento de generación de QR con membresía no válida', {
        usuarioId,
        estado: membership.estado,
        razon:  membership.razon,
      });

      // HTTP 402 Payment Required (según requerimiento explícito Tarea 3.2)
      return res.status(402).json({
        success: false,
        data: {
          usuario_id:   usuarioId,
          estado_actual: membership.estado,
          requiere_pago: true,
        },
        error: membership.razon || 'Membresía vencida o con adeudos pendientes. Por favor realiza tu pago para ingresar.',
      });
    }

    // 2. Generar payload con marca de tiempo actual y nonce (jti) único
    const timestamp = Date.now();
    const nonce     = cryptoService.generateNonce();

    const payload = {
      usuario_id: usuarioId,
      timestamp,
      nonce,
    };

    // 3. Cifrar con AES-256-GCM
    const tokenQr = cryptoService.encryptQrPayload(payload);

    // 4. Calcular timestamp de expiración (30 segundos exactos)
    const ttlSeconds = env.QR_TTL_SECONDS || 30;
    const expiresAt  = new Date(timestamp + ttlSeconds * 1000).toISOString();

    logger.info('Código QR dinámico generado exitosamente', {
      usuarioId,
      nonce: nonce.substring(0, 8),
      expiresAt,
    });

    return res.status(200).json({
      success: true,
      data: {
        token_qr:      tokenQr,
        ttl_segundos:  ttlSeconds,
        generado_en:   new Date(timestamp).toISOString(),
        expira_en:     expiresAt,
        membresía: {
          estado:       membership.estado,
          valido_hasta: membership.valido_hasta,
        },
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/qr/verify ────────────────────────────────────────────────────
/**
 * Verifica un token QR escaneado por la lectora del torniquete y decide si abre la puerta.
 * Protegido por TURNSTILE_API_KEY en middleware de hardware.
 */
async function verifyQr(req, res, next) {
  try {
    const { token_qr } = req.body;

    if (!token_qr) {
      return res.status(400).json({
        success: false, data: null, error: 'Token QR (token_qr) requerido.',
      });
    }

    let payload;
    try {
      // 1. Desencriptar con AES-256-GCM (valida integridad Auth Tag)
      payload = cryptoService.decryptQrPayload(token_qr);
    } catch (cryptoErr) {
      // Registrar intento de acceso fallido por token corrupto/alterado
      logger.warn('Intento de acceso con QR dañado o falsificado', { error: cryptoErr.message });
      return res.status(403).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: 'Código QR inválido o manipulado.',
      });
    }

    const { usuario_id, timestamp, nonce } = payload;
    const ahora = Date.now();
    const edadMs = ahora - timestamp;
    const ttlMs  = (env.QR_TTL_SECONDS || 30) * 1000;

    // 2. Verificar que el token no haya expirado (30 segundos estrictos)
    if (edadMs > ttlMs) {
      await accessModel.recordAccess({
        usuarioId:       usuario_id,
        tokenCodigo:     nonce,
        metodoAcceso:    'qr',
        accesoConcedido: false,
        razonRechazo:    `QR expirado (generado hace ${Math.round(edadMs / 1000)}s, límite ${env.QR_TTL_SECONDS}s).`,
      }, req.redisClient);

      return res.status(403).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: `El código QR ha expirado (límite de ${env.QR_TTL_SECONDS} segundos). Por favor genera uno nuevo en tu app.`,
      });
    }

    // Proteger contra relojes adelantados (más de 5 segundos en el futuro)
    if (edadMs < -5000) {
      return res.status(403).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: 'El reloj del dispositivo no está sincronizado con el servidor.',
      });
    }

    // 3. Verificar que el nonce no se haya utilizado antes (Anti-Replay Attack)
    const isUsed = await accessModel.isNonceAlreadyUsed(nonce, req.redisClient);
    if (isUsed) {
      logger.warn('Intento de ataque de repetición: QR ya escaneado previamente', { usuario_id, nonce });
      await accessModel.recordAccess({
        usuarioId:       usuario_id,
        tokenCodigo:     nonce,
        metodoAcceso:    'qr',
        accesoConcedido: false,
        razonRechazo:    'Código QR duplicado / Replay Attack detectado.',
      }, req.redisClient);

      return res.status(403).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: 'Este código QR ya fue utilizado para ingresar. Por favor genera uno nuevo.',
      });
    }

    // 4. Doble verificación de membresía al momento exacto de abrir (por si venció o se canceló hace segundos)
    const membership = await paymentClientService.checkMembershipValidity(usuario_id, req.redisClient);
    if (!membership.valid) {
      await accessModel.recordAccess({
        usuarioId:       usuario_id,
        tokenCodigo:     nonce,
        metodoAcceso:    'qr',
        accesoConcedido: false,
        razonRechazo:    `Membresía vencida en torniquete: ${membership.razon}`,
      }, req.redisClient);

      return res.status(402).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: membership.razon || 'Membresía vencida o con adeudos.',
      });
    }

    // 5. Conceder acceso y registrar en el historial del usuario
    await accessModel.recordAccess({
      usuarioId:       usuario_id,
      tokenCodigo:     nonce,
      metodoAcceso:    'qr',
      accesoConcedido: true,
      razonRechazo:    null,
    }, req.redisClient);

    logger.info('ACCESO CONCEDIDO — Apertura de torniquete activada', {
      usuarioId:  usuario_id,
      torniquete: req.turnstile?.id || 'torniquete_principal',
    });

    return res.status(200).json({
      success: true,
      data: {
        acceso_concedido:    true,
        apertura_torniquete: true,
        usuario_id:          usuario_id,
        tiempo_respuesta_ms: Date.now() - ahora,
        mensaje:             '¡Bienvenido a GymPro! Acceso autorizado.',
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  generateQr,
  verifyQr,
};
