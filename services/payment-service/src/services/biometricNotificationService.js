/**
 * @file services/payment-service/src/services/biometricNotificationService.js
 * @description Notificador hacia el microservicio access-service (ZKTeco ADMS)
 * para sincronización y eliminación instantánea de rostros autorizados o expirados.
 */

'use strict';

const axios                   = require('axios');
const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:biometricNotifier');

/**
 * Notifica al access-service en Railway que sincronice (DATA UPDATE BIODATA/USERINFO)
 * el rostro de un socio en las terminales ZKTeco SpeedFace-V5L tras un pago exitoso.
 *
 * @param {string} usuarioId - UUID del usuario
 * @param {string|number} pin - PIN de terminal asignado al usuario
 * @param {string} nombre - Nombre completo del socio
 */
async function notifyBiometricSync(usuarioId, pin, nombre) {
  if (!usuarioId || !pin) return;

  const accessServiceUrl = process.env.ACCESS_SERVICE_URL || 'http://localhost:3002';
  const apiKey           = process.env.TURNSTILE_API_KEY || 'turnstile_secret_key_prod_2026';

  try {
    logger.info('Solicitando sincronización facial ZKTeco a access-service...', { usuarioId, pin });
    await axios.post(
      `${accessServiceUrl.rstrip('/')}/api/v1/adms/sync-user`,
      {
        usuario_id: usuarioId,
        pin:        pin,
        nombre:     nombre || 'Socio GymPro',
      },
      {
        headers: {
          'X-Turnstile-API-Key': apiKey,
          'Content-Type':        'application/json',
        },
        timeout: 3000,
      }
    );
    logger.info('Sincronización facial ZKTeco solicitada exitosamente', { usuarioId, pin });
  } catch (err) {
    // No romper el flujo del webhook de Stripe en caso de fallo de red puntual
    logger.error('Error notificando sincronización facial ZKTeco a access-service', {
      usuarioId, pin, error: err.message,
    });
  }
}

/**
 * Notifica al access-service que elimine inmediatamente (DATA DELETE BIODATA/USERINFO)
 * el rostro de un socio en las terminales biométricas por vencimiento o impago.
 *
 * @param {string} usuarioId - UUID del usuario
 * @param {string|number} pin - PIN de terminal del usuario
 */
async function notifyBiometricDelete(usuarioId, pin) {
  if (!usuarioId || !pin) return;

  const accessServiceUrl = process.env.ACCESS_SERVICE_URL || 'http://localhost:3002';
  const apiKey           = process.env.TURNSTILE_API_KEY || 'turnstile_secret_key_prod_2026';

  try {
    logger.warn('⚠️ Solicitando revocación y borrado facial ZKTeco instantáneo...', { usuarioId, pin });
    await axios.post(
      `${accessServiceUrl.rstrip('/')}/api/v1/adms/delete-user`,
      {
        usuario_id: usuarioId,
        pin:        pin,
      },
      {
        headers: {
          'X-Turnstile-API-Key': apiKey,
          'Content-Type':        'application/json',
        },
        timeout: 3000,
      }
    );
    logger.info('Borrado facial ZKTeco solicitado exitosamente', { usuarioId, pin });
  } catch (err) {
    logger.error('Error notificando borrado facial ZKTeco a access-service', {
      usuarioId, pin, error: err.message,
    });
  }
}

// Pequeño helper de String por si rstrip no existe en prototipo de JS
String.prototype.rstrip = function (char = '/') {
  return this.replace(new RegExp(`${char}+$`), '');
};

module.exports = {
  notifyBiometricSync,
  notifyBiometricDelete,
};
