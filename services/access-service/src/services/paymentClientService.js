/**
 * @file services/access-service/src/services/paymentClientService.js
 * @description Cliente inter-servicios resiliente para verificar vigencia de membresía.
 *
 * Implementa una estrategia en 3 niveles (Cache-First + Inter-Service API + DB Fallback)
 * para asegurar baja latencia (< 50ms habitualmente) y alta disponibilidad incluso
 * si el microservicio de pagos sufre caídas temporales o degradación de red.
 */

'use strict';

const env                   = require('../config/environment');
const { getSupabaseClient } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:paymentClient');

/**
 * Consulta la vigencia de la membresía de un usuario.
 *
 * @param {string} usuarioId - UUID del usuario
 * @param {import('ioredis').Redis|null} redisClient - Instancia de Redis (opcional)
 * @returns {Promise<{ valid: boolean, estado: string, valido_hasta: string|null, razon?: string }>}
 */
async function checkMembershipValidity(usuarioId, redisClient = null) {
  const cacheKey = `access:membership_status:${usuarioId}`;

  // ── 1. Cache Redis (TTL: 60s) — Ultra rápido (< 5ms) ──────────────────────
  if (redisClient) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        const status = JSON.parse(cached);
        // Validar si la fecha cacheada aún no ha expirado
        if (status.valid && new Date(status.valido_hasta) > new Date()) {
          return status;
        }
      }
    } catch (cacheErr) {
      logger.warn('Fallo al leer caché de membresía en Redis', { error: cacheErr.message });
    }
  }

  // ── 2. Petición HTTP Inter-Servicio a payment-service (con Timeout corto) ──
  try {
    const url = `${env.PAYMENT_SERVICE_INTERNAL_URL}/api/v1/subscriptions/active?userId=${encodeURIComponent(usuarioId)}`;
    const controller = new AbortController();
    const timeoutId  = setTimeout(() => controller.abort(), env.INTER_SERVICE_TIMEOUT_MS || 2000);

    const response = await fetch(url, {
      method:  'GET',
      headers: {
        'x-inter-service-secret': env.INTER_SERVICE_SECRET,
        'Accept':                 'application/json',
      },
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (response.status === 200) {
      const { data } = await response.json();
      const statusResult = {
        valid:        true,
        estado:       data.estado,
        valido_hasta: data.valido_hasta,
      };
      if (redisClient) {
        await redisClient.setex(cacheKey, 60, JSON.stringify(statusResult));
      }
      return statusResult;
    } else if (response.status === 403 || response.status === 404 || response.status === 402) {
      const errJson = await response.json().catch(() => ({ error: 'Membresía no válida.' }));
      return {
        valid:        false,
        estado:       'expired',
        valido_hasta: null,
        razon:        errJson.error || 'La membresía ha expirado o tiene adeudos pendientes.',
      };
    }
  } catch (httpErr) {
    logger.warn('Petición HTTP a payment-service fallida o en timeout, activando fallback a DB', {
      error: httpErr.message,
    });
  }

  // ── 3. Fallback directo a DB (payment_service_db.suscripciones) ───────────
  // Garantiza que el torniquete no bloquee la entrada si la API HTTP tuvo un bache temporal
  try {
    const db = getSupabaseClient();
    const ahoraIso = new Date().toISOString();

    const { data: sub, error } = await db
      .from('payment_service_db.suscripciones')
      .select('estado, valido_hasta')
      .eq('usuario_id', usuarioId)
      .in('estado', ['active', 'free_pass'])
      .gt('valido_hasta', ahoraIso)
      .order('valido_hasta', { ascending: false })
      .limit(1)
      .single();

    if (error || !sub) {
      return {
        valid:        false,
        estado:       'expired_or_none',
        valido_hasta: null,
        razon:        'No se encontró una membresía activa y vigente para este usuario.',
      };
    }

    const statusResult = {
      valid:        true,
      estado:       sub.estado,
      valido_hasta: sub.valido_hasta,
    };

    if (redisClient) {
      await redisClient.setex(cacheKey, 60, JSON.stringify(statusResult));
    }
    return statusResult;
  } catch (dbErr) {
    logger.error('Error crítico en fallback a DB para validar membresía', { error: dbErr.message });
    throw new Error('No fue posible verificar el estado de la membresía en este momento.');
  }
}

module.exports = { checkMembershipValidity };
