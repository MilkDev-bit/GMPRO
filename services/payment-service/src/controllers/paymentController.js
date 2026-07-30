/**
 * @file services/payment-service/src/controllers/paymentController.js
 * @description Controladores de pago: pagos en efectivo (recepcionista), sesiones de checkout (Stripe) y recibos en PDF.
 */

'use strict';

const { getStripeClient } = require('../config/stripe');
const env                 = require('../config/environment');
const subscriptionModel   = require('../models/subscriptionModel');
const paymentHistoryModel = require('../models/paymentHistoryModel');
const offerModel          = require('../models/offerModel');
const accessSyncService   = require('../services/accessSyncService');
const { generateReceiptPdf } = require('../services/pdfService');
const { query } = require('../config/database');   // pg directo (svc_payment)
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:paymentController');

// ── POST /api/v1/payments/cash-payment ────────────────────────────────────────
// (También disponible en /api/v1/cash-payment)
/**
 * Registra un pago en efectivo realizado en la recepción del gimnasio.
 * Protegido por API Key en apiKeyAuth middleware.
 *
 * Coloca metodo_pago: 'cash', estado: 'active' y calcula valido_hasta (+30 días por defecto
 * o según plan_duracion_dias). Si ya tiene una suscripción activa, la renueva
 * extendiendo la fecha de expiración desde la actual.
 */
async function registerCashPayment(req, res, next) {
  try {
    const {
      usuario_id,
      plan_id,
      monto_cobrado,
      metodo_pago = 'cash',   // 'cash' | 'card_terminal' | 'transfer'
      notas = null,
    } = req.body;

    const receptionistId = req.receptionista?.id || 'reception_unknown';

    // ── Idempotencia (2.2): la clave viene por header o body ─────────────────
    const idempotencyKey = req.headers['idempotency-key'] || req.body.idempotency_key;
    if (!idempotencyKey || String(idempotencyKey).length < 8) {
      return res.status(400).json({
        success: false, data: null,
        error: 'Idempotency-Key requerida (header Idempotency-Key o body idempotency_key, mín. 8 caracteres).',
      });
    }

    // ── Verificación REAL de usuario (2.2b): schema correcto + corte a 400 ───
    // Antes: db.from('auth_service_db.usuarios') — string con punto que NO
    // resuelve como schema.tabla; la verificación nunca bloqueaba. Ahora se
    // usa .schema('auth_service_db').from('usuarios') y se CORTA si no existe.
    let usuario;
    try {
      const { rows } = await query(
        `SELECT id, email, nombre, apellido_paterno
         FROM auth_service_db.usuarios
         WHERE id = $1 AND eliminado_en IS NULL
         LIMIT 1`,
        [usuario_id],
      );
      usuario = rows[0];
    } catch (userError) {
      logger.error('Error verificando usuario para pago en efectivo', {
        usuario_id, receptionistId, error: userError.message,
      });
      return res.status(502).json({
        success: false, data: null,
        error: 'No se pudo verificar el usuario. Intenta de nuevo.',
      });
    }
    if (!usuario) {
      logger.warn('Pago en efectivo rechazado: usuario inexistente', { usuario_id, receptionistId });
      return res.status(400).json({
        success: false, data: null,
        error: 'El usuario indicado no existe o está dado de baja.',
      });
    }

    // Folio del recibo (se genera aquí y se pasa a la RPC para atomicidad).
    const numeroRecibo = paymentHistoryModel.generateReceiptFolio(metodo_pago);

    // ── Registro ATÓMICO e IDEMPOTENTE (2.2 + 2.3) ───────────────────────────
    // La RPC deriva la duración del PLAN (no del cliente), calcula la
    // variacion_precio contra el precio de referencia, extiende/crea la
    // suscripción e inserta el asiento en una sola transacción.
    let result;
    try {
      result = await subscriptionModel.registerCashPayment({
        usuarioId:       usuario_id,
        planId:          plan_id,
        montoCobrado:    Number(monto_cobrado),
        metodoPago:      metodo_pago,
        receptionistaId: receptionistId,
        idempotencyKey:  String(idempotencyKey),
        numeroRecibo,
        notas,
      });
    } catch (err) {
      if (err.code === 'PLAN_NOT_FOUND') {
        return res.status(400).json({
          success: false, data: null,
          error: 'El plan indicado no existe o no está activo.',
        });
      }
      throw err;
    }

    const { subscription, pago, action, yaProcesado } = result;

    // Reintento idempotente: el pago ya se había procesado. NO se re-acuña
    // cortesía ni se re-extiende nada; se devuelve el registro existente.
    if (yaProcesado) {
      logger.info('Pago en efectivo idempotente: se devuelve el registro existente', {
        usuario_id, receptionistId, historialPagoId: pago?.id,
      });
      return res.status(200).json({
        success: true,
        data: {
          idempotente:       true,
          suscripcion_id:    subscription?.id,
          historial_pago_id: pago?.id,
          numero_recibo:     pago?.numero_recibo,
          valido_hasta:      subscription?.valido_hasta,
        },
        error: null,
      });
    }

    // Efectos posteriores SOLO en primer procesamiento.
    const cortesia = await accessSyncService.mintCourtesyPass(usuario_id);

    await accessSyncService.invalidateMembershipCache(
      usuario_id,
      subscription.valido_hasta,
    );

    const asiento = pago;

    logger.info('Pago presencial registrado, suscripción activada y acceso sincronizado', {
      action,
      subscriptionId: subscription.id,
      historialPagoId: asiento.id,
      usuario_id,
      receptionistId,
      validoHasta: subscription.valido_hasta,
      cortesiaEmitida: !!cortesia,
    });

    // 6. Nombre legible del socio para el ticket físico.
    const nombreSocio = usuario
      ? `${usuario.nombre || 'Socio'} ${usuario.apellido_paterno || ''}`.trim()
      : 'Socio GymPro';

    // 7. Payload estructurado para la impresora térmica de mostrador
    //    (compatible con printDailyTicket del reception-hardware-controller).
    const ticketImpresion = {
      tipo:            'pago_presencial',
      user_name:       nombreSocio,
      numero_recibo:   asiento.numero_recibo,
      monto:           Number(asiento.monto),
      moneda:          asiento.moneda || 'MXN',
      metodo_pago:     metodo_pago,
      plan_nombre:     subscription.plan_nombre,
      valido_hasta:    subscription.valido_hasta,
      // Pase de cortesía del día (QR imprimible). Puede ser null si access-service no respondió.
      codigo_ticket:   cortesia?.codigo_ticket || null,
      qr_string:       cortesia?.qr_string || null,
      vigencia_horas:  cortesia?.vigencia_horas || null,
      notas:           `Recibo ${asiento.numero_recibo}`,
    };

    return res.status(action === 'created' ? 201 : 200).json({
      success: true,
      data: {
        accion:            action === 'created' ? 'creada' : 'renovada',
        suscripcion_id:    subscription.id,
        historial_pago_id: asiento.id,
        numero_recibo:     asiento.numero_recibo,
        usuario_id:        subscription.usuario_id,
        plan_nombre:       subscription.plan_nombre,
        metodo_pago:       metodo_pago,
        estado:            subscription.estado,
        valido_desde:      subscription.valido_desde,
        valido_hasta:      subscription.valido_hasta,
        atendido_por:      receptionistId,
        monto_pagado:      Number(asiento.monto),
        variacion_precio:  asiento.variacion_precio != null ? Number(asiento.variacion_precio) : null,
        acceso_sincronizado: true,
        pase_cortesia:     cortesia || null,
        // Objeto listo para enviar a la impresora térmica local (POST /print-ticket).
        ticket_impresion:  ticketImpresion,
        recibo_pdf_url:    `/api/v1/payments/${subscription.id}/receipt`,
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── Canje de cupones: validación en BD + mapeo a Stripe ───────────────────────

/**
 * Valida una oferta contra la BD (existencia, estado, vigencia y cupo).
 * @returns {Promise<{offer: object}|{error: string}>}
 */
async function validateOffer(offerCode) {
  const offer = await offerModel.findByCodigo(offerCode);
  if (!offer)         return { error: 'El código promocional no existe.' };
  if (!offer.activa)  return { error: 'El código promocional no está activo.' };

  const now = Date.now();
  if (new Date(offer.valido_desde).getTime() > now)
    return { error: 'El código promocional aún no está vigente.' };
  if (new Date(offer.valido_hasta).getTime() < now)
    return { error: 'El código promocional ha expirado.' };
  if (offer.max_usos != null && Number(offer.usos) >= Number(offer.max_usos))
    return { error: 'El código promocional ha alcanzado su límite de usos.' };

  return { offer };
}

/**
 * Garantiza que exista un Coupon de Stripe cuyo id sea el código de la oferta,
 * creándolo "al vuelo" (idempotente) a partir de tipo/valor de la oferta:
 *   • porcentaje  → percent_off (duration: once)
 *   • monto_fijo  → amount_off en centavos + currency (duration: once)
 *   • meses_gratis→ percent_off 100, duration repeating N meses
 * @returns {Promise<string>} el id del cupón de Stripe (== offer.codigo)
 */
async function ensureStripeCoupon(stripe, offer) {
  const couponId = offer.codigo;
  try {
    await stripe.coupons.retrieve(couponId);
    return couponId; // Ya existe → reutilizar
  } catch (e) {
    if (e.statusCode !== 404 && e.code !== 'resource_missing') throw e;
  }

  const params = { id: couponId, name: offer.nombre };
  if (offer.tipo === 'porcentaje') {
    params.percent_off = Number(offer.valor);
    params.duration    = 'once';
  } else if (offer.tipo === 'monto_fijo') {
    params.amount_off = Math.round(Number(offer.valor) * 100);
    params.currency   = (process.env.STRIPE_DEFAULT_CURRENCY || 'usd').toLowerCase();
    params.duration   = 'once';
  } else { // meses_gratis
    params.percent_off        = 100;
    params.duration           = 'repeating';
    params.duration_in_months = Math.max(1, Math.round(Number(offer.valor)));
  }

  await stripe.coupons.create(params, { idempotencyKey: `gympro:coupon:${couponId}` });
  return couponId;
}

// ── POST /api/v1/payments/create-checkout-session ─────────────────────────────
/**
 * Crea una sesión de Stripe Checkout para pago en línea (tarjeta).
 * Acepta `offerCode` opcional (cupón promocional). Requiere JWT de usuario.
 */
async function createCheckoutSession(req, res, next) {
  try {
    const { priceId, successUrl, cancelUrl, offerCode } = req.body;
    const userId    = req.user.id;
    const userEmail = req.user.email;

    const stripe = getStripeClient();

    // 0. Canje de cupón (opcional): validar en BD y mapear a un cupón de Stripe.
    //    El descuento NO se consume aquí; el contador de usos se incrementa en el
    //    webhook checkout.session.completed (solo cuando el pago se completa).
    let couponId = null;
    let offerCodeNormalized = null;
    if (offerCode) {
      const result = await validateOffer(offerCode);
      if (result.error) {
        return res.status(400).json({ success: false, data: null, error: result.error });
      }
      offerCodeNormalized = result.offer.codigo;
      couponId = await ensureStripeCoupon(stripe, result.offer);
    }

    // 1. Verificar si el usuario ya tiene o tuvo suscripción con stripe_customer_id
    const history = await subscriptionModel.getHistoryByUserId(userId, 1);
    let customerId = history.find((s) => s.stripe_customer_id)?.stripe_customer_id;

    if (!customerId) {
      // Crear nuevo customer en Stripe.
      // Idempotency-Key estable por usuario: un doble clic (o reintento de red) NO
      // crea dos customers en Stripe — devuelve el mismo objeto ya creado.
      const customer = await stripe.customers.create(
        {
          email:    userEmail,
          metadata: { gympro_user_id: userId },
        },
        { idempotencyKey: `gympro:customer:${userId}` },
      );
      customerId = customer.id;
    }

    // 2. Crear sesión de Checkout.
    // Idempotency-Key por (usuario, plan, ventana de 30s): los dobles clics rápidos
    // colapsan en UNA sola sesión de checkout → evita cobros/sesiones duplicadas.
    const idemBucket = Math.floor(Date.now() / 30_000);
    const sessionParams = {
      customer:     customerId,
      payment_method_types: ['card'],
      mode:         'subscription',
      line_items:   [{ price: priceId, quantity: 1 }],
      success_url:  successUrl || 'https://app.gympro.com/payment/success?session_id={CHECKOUT_SESSION_ID}',
      cancel_url:   cancelUrl  || 'https://app.gympro.com/payment/cancel',
      subscription_data: {
        metadata: { gympro_user_id: userId },
      },
      metadata: { gympro_user_id: userId },
    };

    // Inyectar el descuento y registrar el código en metadata para que el
    // webhook (checkout.session.completed) pueda contabilizar el canje.
    if (couponId) {
      sessionParams.discounts = [{ coupon: couponId }];
      sessionParams.metadata.offer_code = offerCodeNormalized;
      sessionParams.subscription_data.metadata.offer_code = offerCodeNormalized;
    }

    const session = await stripe.checkout.sessions.create(
      sessionParams,
      // El código entra en la idem-key: un reintento con distinto cupón NO colapsa
      // en una sesión previa sin descuento.
      { idempotencyKey: `gympro:checkout:${userId}:${priceId}:${offerCodeNormalized || 'none'}:${idemBucket}` },
    );

    logger.info('Stripe Checkout Session creada', {
      sessionId: session.id,
      userId,
      customerId,
      offerCode: offerCodeNormalized || null,
    });

    return res.status(200).json({
      success: true,
      data: {
        sessionId: session.id,
        url:       session.url,
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── GET /api/v1/payments/:id/receipt ──────────────────────────────────────────
/**
 * Descarga el recibo de pago en formato PDF.
 * Si es el usuario autenticado (O el recepcionista con API key), permite la descarga.
 */
async function getReceiptPdf(req, res, next) {
  try {
    const { id: subscriptionId } = req.params;

    let subscription = null;
    try {
      const { rows } = await query(`SELECT * FROM suscripciones WHERE id = $1 LIMIT 1`, [subscriptionId]);
      subscription = rows[0] || null;
    } catch (e) {
      subscription = null;
    }

    if (!subscription) {
      return res.status(404).json({
        success: false, data: null, error: 'Comprobante o suscripción no encontrada.',
      });
    }

    // Seguridad: el usuario con JWT solo puede descargar sus propios recibos
    if (req.user && req.user.id !== subscription.usuario_id && req.user.role !== 'admin') {
      return res.status(403).json({
        success: false, data: null, error: 'No tienes permiso para ver este recibo.',
      });
    }

    // Obtener datos del usuario si se puede
    let user = { nombre: 'Usuario GymPro', email: '' };
    try {
      const { rows } = await query(
        `SELECT nombre, apellido_paterno, email FROM auth_service_db.usuarios WHERE id = $1 LIMIT 1`,
        [subscription.usuario_id],
      );
      if (rows[0]) user = rows[0];
    } catch { /* si falla, se usa el default */ }

    const pdfBuffer = await generateReceiptPdf({
      subscription,
      user,
      receptionistId: subscription.receptionist_id,
    });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="GymPro_Recibo_${subscription.id.substring(0,8)}.pdf"`);
    return res.send(pdfBuffer);
  } catch (err) {
    next(err);
  }
}

module.exports = {
  registerCashPayment,
  createCheckoutSession,
  getReceiptPdf,
};
