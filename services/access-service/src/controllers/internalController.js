/**
 * @file services/access-service/src/controllers/internalController.js
 * @description Endpoints internos consumidos por payment-service tras un pago
 * presencial, para lograr el desbloqueo INSTANTÁNEO del socio:
 *
 *   1. POST /internal/invalidate-membership-cache
 *      Borra (y opcionalmente pre-calienta) la clave Redis de vigencia de
 *      membresía que usa paymentClientService.checkMembershipValidity, de modo
 *      que el próximo escaneo en el torniquete NO devuelva el estado cacheado
 *      de "vencido" durante hasta 60s.
 *
 *   2. POST /internal/courtesy-pass
 *      Acuña un pase de cortesía (tickets_visitas) válido hasta el fin del día,
 *      cuyo codigo_ticket se imprime en el ticket térmico de mostrador. Permite
 *      el ingreso inmediato aunque el móvil del socio aún no haya sincronizado.
 */

'use strict';

const accessModel             = require('../models/accessModel');
const crypto                  = require('crypto');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:internalController');

const CACHE_PREFIX = 'access:membership_status:';

// ── POST /api/v1/access/internal/invalidate-membership-cache ─────────────────
async function invalidateMembershipCache(req, res, next) {
  try {
    const { usuario_id, valido_hasta = null, estado = 'active' } = req.body;

    if (!usuario_id) {
      return res.status(400).json({
        success: false, data: null, error: 'usuario_id es requerido.',
      });
    }

    const cacheKey = `${CACHE_PREFIX}${usuario_id}`;
    let action = 'noop';

    if (req.redisClient) {
      // 1. Invalidar el estado potencialmente obsoleto ('expired' cacheado)
      await req.redisClient.del(cacheKey);
      action = 'invalidated';

      // 2. Pre-calentar con el estado vigente para que el PRIMER escaneo tras el
      //    pago sea instantáneo (< 5ms) y no dependa del round-trip a payment.
      if (valido_hasta) {
        const warm = { valid: true, estado, valido_hasta };
        await req.redisClient.setex(cacheKey, 60, JSON.stringify(warm));
        action = 'invalidated_and_prewarmed';
      }
    }

    logger.info('Caché de membresía sincronizada tras pago presencial', {
      usuario_id, action, valido_hasta,
    });

    return res.status(200).json({
      success: true,
      data: { usuario_id, action, cache_key: cacheKey },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/access/internal/courtesy-pass ───────────────────────────────
async function mintCourtesyPass(req, res, next) {
  try {
    const { usuario_id = null, notas = 'Pase de cortesía por pago en mostrador' } = req.body;

    // Vigencia: hasta el fin del día local (pase de "ese único día").
    const ahora    = new Date();
    const finDelDia = new Date(ahora);
    finDelDia.setHours(23, 59, 59, 999);

    // Código legible y escaneable (mismo formato que ticketController).
    const rnd = crypto.randomBytes(8).toString('hex').toUpperCase();
    const codigoTicket = `GP-${rnd.substring(0, 4)}-${rnd.substring(4, 8)}-${rnd.substring(8, 12)}`;

    const ticket = await accessModel.createTicketRecord({
      usuario_id,
      codigo_ticket: codigoTicket,
      expira_en:     finDelDia.toISOString(),
      notas,
    });

    logger.info('Pase de cortesía acuñado tras pago presencial', {
      usuario_id, codigo: ticket.codigo_ticket, expira_en: ticket.expira_en,
    });

    return res.status(201).json({
      success: true,
      data: {
        codigo_ticket: ticket.codigo_ticket,
        qr_string:     ticket.codigo_ticket,
        estado:        ticket.estado,
        expira_en:     ticket.expira_en,
        vigencia_horas: Math.max(1, Math.round((finDelDia - ahora) / 3_600_000)),
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = { invalidateMembershipCache, mintCourtesyPass };
