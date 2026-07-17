/**
 * @file services/payment-service/src/services/accessSyncService.js
 * @description Cliente inter-servicio (payment-service → access-service) para el
 * desbloqueo INSTANTÁNEO tras un pago presencial:
 *
 *   • invalidateMembershipCache(): borra/pre-calienta la caché de vigencia en
 *     access-service para que el torniquete no siga viendo "vencido" hasta 60s.
 *   • mintCourtesyPass(): acuña un pase de cortesía del día para imprimir en el
 *     ticket térmico (ingreso inmediato aunque el móvil no haya sincronizado).
 *
 * DISEÑO RESILIENTE: ambas llamadas son "best-effort" con timeout corto. Si
 * access-service está caído, NO se lanza excepción hacia el recepcionista: el
 * pago ya quedó registrado y la vigencia es consultable por el fallback a DB del
 * propio access-service. Se registra la degradación para observabilidad.
 */

'use strict';

const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:accessSync');

const BASE_URL = (env.ACCESS_SERVICE_INTERNAL_URL || '').replace(/\/+$/, '');
const TIMEOUT_MS = env.INTER_SERVICE_TIMEOUT_MS || 2500;

/**
 * POST helper con secreto inter-servicio y timeout por AbortController.
 * @returns {Promise<{ ok: boolean, status: number, body: any }>}
 */
async function postInternal(path, payload) {
  const controller = new AbortController();
  const timeoutId  = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${BASE_URL}${path}`, {
      method:  'POST',
      headers: {
        'Content-Type':            'application/json',
        'x-inter-service-secret':  env.INTER_SERVICE_SECRET,
        'Accept':                  'application/json',
      },
      body:   JSON.stringify(payload),
      signal: controller.signal,
    });
    const body = await response.json().catch(() => ({}));
    return { ok: response.ok, status: response.status, body };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Invalida (y pre-calienta) la caché de vigencia de membresía del socio.
 * @param {string} usuarioId
 * @param {string|null} validoHasta - ISO8601 de expiración para pre-calentar
 * @returns {Promise<boolean>} true si la sincronización tuvo éxito
 */
async function invalidateMembershipCache(usuarioId, validoHasta = null) {
  if (!BASE_URL) {
    logger.warn('ACCESS_SERVICE_INTERNAL_URL no configurada; se omite invalidación de caché.');
    return false;
  }
  try {
    const { ok, status } = await postInternal('/invalidate-membership-cache', {
      usuario_id:   usuarioId,
      valido_hasta: validoHasta,
      estado:       'active',
    });
    if (!ok) {
      logger.warn('access-service rechazó la invalidación de caché', { usuarioId, status });
      return false;
    }
    logger.info('Caché de membresía invalidada en access-service', { usuarioId });
    return true;
  } catch (err) {
    logger.warn('No se pudo invalidar la caché en access-service (degradación tolerada)', {
      usuarioId, error: err.message,
    });
    return false;
  }
}

/**
 * Acuña un pase de cortesía válido por el día en access-service.
 * @param {string} usuarioId
 * @returns {Promise<{ codigo_ticket: string, qr_string: string, expira_en: string, vigencia_horas: number }|null>}
 */
async function mintCourtesyPass(usuarioId) {
  if (!BASE_URL) return null;
  try {
    const { ok, status, body } = await postInternal('/courtesy-pass', {
      usuario_id: usuarioId,
      notas:      'Cortesía por pago en mostrador',
    });
    if (!ok || !body?.data) {
      logger.warn('No se pudo acuñar pase de cortesía', { usuarioId, status });
      return null;
    }
    return body.data;
  } catch (err) {
    logger.warn('Fallo acuñando pase de cortesía (se continúa sin él)', {
      usuarioId, error: err.message,
    });
    return null;
  }
}

module.exports = { invalidateMembershipCache, mintCourtesyPass };
