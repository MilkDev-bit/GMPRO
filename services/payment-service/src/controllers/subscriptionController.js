/**
 * @file services/payment-service/src/controllers/subscriptionController.js
 * @description Controladores para consultas y gestión de suscripciones de usuarios.
 */

'use strict';

const subscriptionModel       = require('../models/subscriptionModel');
const { getStripeClient }     = require('../config/stripe');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:subscriptionController');

// ── GET /api/v1/subscriptions/active ──────────────────────────────────────────
/**
 * Consulta la suscripción activa del usuario autenticado (JWT) o para un usuario específico
 * si es consultado vía comunicación inter-servicio (ej. access-service verificando vigencia).
 */
async function getActiveSubscription(req, res, next) {
  try {
    // Si la llamada viene de otro servicio o un admin pasándole ?userId=... y tiene permisos
    const targetUserId = (req.query.userId && (req.isInterService || req.user?.role === 'admin'))
      ? req.query.userId
      : req.user?.id;

    if (!targetUserId) {
      return res.status(400).json({
        success: false, data: null, error: 'ID de usuario requerido.',
      });
    }

    const activeSubscription = await subscriptionModel.findActiveByUserId(targetUserId);

    if (!activeSubscription) {
      return res.status(404).json({
        success: false,
        data:    null,
        error:   'El usuario no cuenta con una membresía activa en este momento.',
      });
    }

    // Verificar adicionalmente si la fecha de vigencia local ya pasó (por si un cron no limpió)
    const ahora = new Date();
    const validoHasta = new Date(activeSubscription.valido_hasta);

    if (validoHasta < ahora) {
      return res.status(403).json({
        success: false,
        data:    activeSubscription,
        error:   `La membresía expiró el ${validoHasta.toLocaleDateString('es-MX')}.`,
      });
    }

    return res.status(200).json({
      success: true,
      data:    activeSubscription,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

// ── GET /api/v1/subscriptions/history ─────────────────────────────────────────
/**
 * Obtiene el historial de membresías y pagos de un usuario autenticado.
 */
async function getSubscriptionHistory(req, res, next) {
  try {
    const userId = req.user.id;
    const limit  = parseInt(req.query.limit || '20', 10);

    const history = await subscriptionModel.getHistoryByUserId(userId, limit);

    return res.status(200).json({
      success: true,
      data:    history,
      error:   null,
    });
  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/subscriptions/cancel ─────────────────────────────────────────
/**
 * Permite al usuario cancelar la renovación automática de su suscripción en Stripe.
 * El usuario conserva el acceso hasta la fecha valido_hasta (cancel at period end).
 */
async function cancelAutoRenew(req, res, next) {
  try {
    const userId = req.user.id;
    const activeSub = await subscriptionModel.findActiveByUserId(userId);

    if (!activeSub) {
      return res.status(404).json({
        success: false, data: null, error: 'No tienes una membresía activa.',
      });
    }

    if (activeSub.metodo_pago === 'cash' || !activeSub.stripe_subscription_id) {
      return res.status(400).json({
        success: false, data: null,
        error: 'Las membresías pagadas en efectivo expiran automáticamente al término de sus 30 días y no requieren cancelación en línea.',
      });
    }

    const stripe = getStripeClient();
    // Programar cancelación al final del período pagado en Stripe.
    // Idempotency-Key por (suscripción, día): dobles clics en "cancelar" no generan
    // múltiples llamadas de escritura a Stripe.
    const dayBucket = Math.floor(Date.now() / 86_400_000);
    const updatedStripeSub = await stripe.subscriptions.update(
      activeSub.stripe_subscription_id,
      { cancel_at_period_end: true },
      { idempotencyKey: `gympro:cancel:${activeSub.stripe_subscription_id}:${dayBucket}` },
    );

    logger.info('Renovación automática cancelada por el usuario', {
      userId,
      subscriptionId: activeSub.stripe_subscription_id,
      cancelAt: new Date(updatedStripeSub.current_period_end * 1000).toISOString(),
    });

    return res.status(200).json({
      success: true,
      data: {
        mensaje: 'La renovación automática ha sido desactivada. Podrás seguir accediendo al gimnasio hasta el final de tu período contratado.',
        valido_hasta: activeSub.valido_hasta,
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getActiveSubscription,
  getSubscriptionHistory,
  cancelAutoRenew,
};
