/**
 * @file services/payment-service/src/controllers/paymentController.js
 * @description Controladores de pago: pagos en efectivo (recepcionista), sesiones de checkout (Stripe) y recibos en PDF.
 */

'use strict';

const { getStripeClient } = require('../config/stripe');
const env                 = require('../config/environment');
const subscriptionModel   = require('../models/subscriptionModel');
const paymentHistoryModel = require('../models/paymentHistoryModel');
const accessSyncService   = require('../services/accessSyncService');
const { generateReceiptPdf } = require('../services/pdfService');
const { getSupabaseClient } = require('../config/database');
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
      plan_nombre = 'Membresía Mensual Efectivo',
      plan_duracion_dias = 30,
      monto,
      metodo_pago = 'cash',   // 'cash' | 'card_terminal' | 'transfer'
      notas = null,
    } = req.body;

    const receptionistId = req.receptionista?.id || 'reception_unknown';

    // 1. Validar si el usuario existe en el auth-service / DB de usuarios
    // (Por robustez relacional inter-esquemas via service role client o consulta API)
    const db = getSupabaseClient();
    const { data: usuario, error: userError } = await db
      .from('auth_service_db.usuarios')
      .select('id, email, nombre, apellido_paterno')
      .eq('id', usuario_id)
      .is('eliminado_en', null)
      .single();

    // Nota: Si el esquema de Supabase no permite la consulta inter-esquema directa via service role,
    // o el usuario no se encuentra, registramos el pago con el ID proporcionado para no bloquear en recepción,
    // pero logueamos advertencia.
    if (userError || !usuario) {
      logger.warn('Registrando pago en efectivo para ID de usuario no verificado localmente o externo', {
        usuario_id, receptionistId, userError: userError?.message,
      });
    }

    // 2. Registrar o renovar suscripción en payment_service_db
    const { subscription, action } = await subscriptionModel.registerCashPayment({
      usuarioId:        usuario_id,
      planNombre:       plan_nombre,
      planDuracionDias: Number(plan_duracion_dias),
      monto:            Number(monto),
      receptionistaId:  receptionistId,
      notas,
    });

    // 3. Acuñar pase de cortesía del día en access-service (best-effort).
    //    Su codigo_ticket se imprime en el ticket térmico para ingreso inmediato.
    const cortesia = await accessSyncService.mintCourtesyPass(usuario_id);

    // 4. Registrar el asiento inmutable en el ledger historial_pagos.
    const asiento = await paymentHistoryModel.recordCashPayment({
      usuarioId:          usuario_id,
      suscripcionId:      subscription.id,
      monto:              Number(monto),
      metodoPago:         metodo_pago,
      planNombre:         subscription.plan_nombre,
      planDuracionDias:   Number(plan_duracion_dias),
      periodoDesde:       subscription.valido_desde,
      periodoHasta:       subscription.valido_hasta,
      paseCortesiaCodigo: cortesia?.codigo_ticket || null,
      receptionistId,
      notas,
    });

    // 5. Sincronización INMEDIATA: invalidar/pre-calentar la caché de vigencia en
    //    access-service para que el torniquete conceda el paso al instante.
    await accessSyncService.invalidateMembershipCache(
      usuario_id,
      subscription.valido_hasta,
    );

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
      monto:           Number(monto),
      moneda:          'MXN',
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
        monto_pagado:      Number(monto),
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

// ── POST /api/v1/payments/create-checkout-session ─────────────────────────────
/**
 * Crea una sesión de Stripe Checkout para pago en línea (tarjeta).
 * Requiere JWT de usuario.
 */
async function createCheckoutSession(req, res, next) {
  try {
    const { priceId, successUrl, cancelUrl } = req.body;
    const userId    = req.user.id;
    const userEmail = req.user.email;

    const stripe = getStripeClient();

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
    const session = await stripe.checkout.sessions.create(
      {
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
      },
      { idempotencyKey: `gympro:checkout:${userId}:${priceId}:${idemBucket}` },
    );

    logger.info('Stripe Checkout Session creada', {
      sessionId: session.id,
      userId,
      customerId,
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

    const db = getSupabaseClient();
    const { data: subscription, error } = await db
      .from('suscripciones')
      .select('*')
      .eq('id', subscriptionId)
      .single();

    if (error || !subscription) {
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
    const { data: usuario } = await db
      .from('auth_service_db.usuarios')
      .select('nombre, apellido_paterno, email')
      .eq('id', subscription.usuario_id)
      .single();
    if (usuario) user = usuario;

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
