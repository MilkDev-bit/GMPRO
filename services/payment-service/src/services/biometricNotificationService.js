/**
 * @file services/payment-service/src/services/biometricNotificationService.js
 * @description Notificador hacia el microservicio access-service (ZKTeco ADMS)
 * para sincronización y eliminación instantánea de rostros autorizados o expirados.
 *
 * Flujo:
 *   • invoice.paid → notifyBiometricSync()  → DATA UPDATE USERINFO/BIODATA en terminal
 *   • customer.subscription.deleted → notifyBiometricDelete() → DATA DELETE en terminal
 *
 * Este servicio es fire-and-forget: los errores se loguean pero NO bloquean
 * el webhook de Stripe. El sistema ZKTeco reintenta en el siguiente pull de terminal.
 */

'use strict';

const axios                   = require('axios');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:biometricNotifier');

/** Elimina trailing slashes de una URL sin modificar el prototipo de String */
function trimTrailingSlash(url) {
  return String(url).replace(/\/+$/, '');
}

/**
 * Notifica al access-service en Railway que sincronice (DATA UPDATE BIODATA/USERINFO)
 * el rostro de un socio en las terminales ZKTeco SpeedFace-V5L tras un pago exitoso.
 *
 * @param {string} usuarioId  - UUID del usuario
 * @param {number} pin        - PIN de terminal asignado al usuario (obtenido del auth-service)
 * @param {string} nombre     - Nombre completo del socio
 * @param {string} [plantillaBase64] - Plantilla facial en Base64 (opcional, solo si está disponible)
 */
async function notifyBiometricSync(usuarioId, pin, nombre, plantillaBase64 = null) {
  if (!usuarioId || !pin) {
    logger.warn('notifyBiometricSync omitido: falta usuarioId o pin', { usuarioId, pin });
    return;
  }

  const accessServiceUrl = process.env.ACCESS_SERVICE_URL || 'http://localhost:3002';
  const apiKey           = process.env.TURNSTILE_API_KEY  || '';

  try {
    logger.info('Solicitando sincronización facial ZKTeco a access-service...', { usuarioId, pin });

    await axios.post(
      `${trimTrailingSlash(accessServiceUrl)}/api/v1/adms/sync-user`,
      {
        usuario_id:   usuarioId,
        pin:          pin,
        nombre:       nombre || `Socio-${pin}`,
        ...(plantillaBase64 && { plantilla_base64: plantillaBase64 }),
      },
      {
        headers: {
          'X-Turnstile-API-Key': apiKey,
          'Content-Type':        'application/json',
        },
        timeout: 5000,
      }
    );

    logger.info('✅ Sincronización facial ZKTeco encolada exitosamente', { usuarioId, pin });
  } catch (err) {
    // No romper el flujo del webhook de Stripe en caso de fallo de red puntual.
    // El worker de retención revisará suscripciones activas sin pin_terminal asignado.
    logger.error('Error notificando sincronización facial ZKTeco a access-service', {
      usuarioId, pin,
      status: err?.response?.status,
      error:  err.message,
    });
  }
}

/**
 * Notifica al access-service que elimine inmediatamente (DATA DELETE BIODATA/USERINFO)
 * el rostro de un socio en las terminales biométricas por vencimiento o impago.
 *
 * @param {string} usuarioId - UUID del usuario
 * @param {number} pin       - PIN de terminal del usuario
 */
async function notifyBiometricDelete(usuarioId, pin) {
  if (!usuarioId || !pin) {
    logger.warn('notifyBiometricDelete omitido: falta usuarioId o pin', { usuarioId, pin });
    return;
  }

  const accessServiceUrl = process.env.ACCESS_SERVICE_URL || 'http://localhost:3002';
  const apiKey           = process.env.TURNSTILE_API_KEY  || '';

  try {
    logger.warn('⚠️ Solicitando revocación y borrado facial ZKTeco instantáneo...', { usuarioId, pin });

    await axios.post(
      `${trimTrailingSlash(accessServiceUrl)}/api/v1/adms/delete-user`,
      {
        usuario_id: usuarioId,
        pin:        pin,
      },
      {
        headers: {
          'X-Turnstile-API-Key': apiKey,
          'Content-Type':        'application/json',
        },
        timeout: 5000,
      }
    );

    logger.info('✅ Borrado facial ZKTeco encolado exitosamente', { usuarioId, pin });
  } catch (err) {
    logger.error('Error notificando borrado facial ZKTeco a access-service', {
      usuarioId, pin,
      status: err?.response?.status,
      error:  err.message,
    });
  }
}

module.exports = {
  notifyBiometricSync,
  notifyBiometricDelete,
};
