/**
 * @file services/payment-service/src/controllers/adminController.js
 * @description Endpoints de administración financiera (panel staff/admin):
 * resumen, listado de suscripciones, cancelación y cortesía/extensión.
 */

'use strict';

const subscriptionModel = require('../models/subscriptionModel');
const offerModel = require('../models/offerModel');
const { getStripeClient } = require('../config/stripe');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:adminController');

// GET /api/v1/admin/finance/summary
async function financeSummary(req, res, next) {
  try {
    const summary = await subscriptionModel.financeSummary();
    return res.status(200).json({ success: true, data: summary, error: null });
  } catch (err) {
    next(err);
  }
}

// GET /api/v1/admin/subscriptions?estado=
async function listSubscriptions(req, res, next) {
  try {
    const subs = await subscriptionModel.listForAdmin({ estado: req.query.estado || null });
    return res.status(200).json({ success: true, data: subs, error: null });
  } catch (err) {
    next(err);
  }
}

// POST /api/v1/admin/subscriptions/:id/cancel
async function cancelSubscription(req, res, next) {
  try {
    const { id } = req.params;
    const sub = await subscriptionModel.findById(id);
    if (!sub) {
      return res.status(404).json({ success: false, data: null, error: 'Suscripción no encontrada.' });
    }

    // Cancelar también en Stripe (best-effort: si falla, igual cerramos local).
    if (sub.stripe_subscription_id) {
      try {
        await getStripeClient().subscriptions.cancel(sub.stripe_subscription_id);
      } catch (e) {
        logger.warn('No se pudo cancelar en Stripe (se cancela solo en local)', {
          id, error: e.message,
        });
      }
    }

    const updated = await subscriptionModel.cancelById(id);
    logger.info('Suscripción cancelada por admin', { adminId: req.user.id, id });
    return res.status(200).json({ success: true, data: updated, error: null });
  } catch (err) {
    next(err);
  }
}

// POST /api/v1/admin/subscriptions/:id/extend  { dias }
async function extendSubscription(req, res, next) {
  try {
    const { id } = req.params;
    const dias = Number(req.body.dias);
    const updated = await subscriptionModel.extendById(id, dias);
    logger.info('Cortesía otorgada por admin', { adminId: req.user.id, id, dias });
    return res.status(200).json({ success: true, data: updated, error: null });
  } catch (err) {
    next(err);
  }
}

// ── Ofertas / cupones ────────────────────────────────────────────────────────

// GET /api/v1/admin/offers
async function listOffers(req, res, next) {
  try {
    const offers = await offerModel.listOffers();
    return res.status(200).json({ success: true, data: offers, error: null });
  } catch (err) {
    next(err);
  }
}

// POST /api/v1/admin/offers
async function createOffer(req, res, next) {
  try {
    const { nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos } = req.body;
    const offer = await offerModel.createOffer({
      nombre, codigo, tipo, valor, valido_desde, valido_hasta,
      max_usos: max_usos ?? null,
    });
    logger.info('Oferta creada por admin', { adminId: req.user.id, codigo, tipo });
    return res.status(201).json({ success: true, data: offer, error: null });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ success: false, data: null, error: 'Ya existe una oferta con ese código.' });
    }
    next(err);
  }
}

// PATCH /api/v1/admin/offers/:id  { activa }
async function setOfferActive(req, res, next) {
  try {
    const { id } = req.params;
    const updated = await offerModel.setActive(id, req.body.activa);
    if (!updated) {
      return res.status(404).json({ success: false, data: null, error: 'Oferta no encontrada.' });
    }
    return res.status(200).json({ success: true, data: updated, error: null });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  financeSummary,
  listSubscriptions,
  cancelSubscription,
  extendSubscription,
  listOffers,
  createOffer,
  setOfferActive,
};
