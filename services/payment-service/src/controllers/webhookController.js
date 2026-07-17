/**
 * @file services/payment-service/src/controllers/webhookController.js
 * @description Handler de webhooks de Stripe.
 *
 * ╔════════════════════════════════════════════════════════════════════════════╗
 * ║  SEGURIDAD CRÍTICA — VERIFICACIÓN DE FIRMA                               ║
 * ║                                                                            ║
 * ║  Stripe firma cada evento con HMAC-SHA256 usando STRIPE_WEBHOOK_SECRET.   ║
 * ║  stripe.webhooks.constructEvent() verifica esa firma y lanza excepción    ║
 * ║  si el payload fue manipulado o el secret no coincide.                    ║
 * ║                                                                            ║
 * ║  ⚠️  PREREQUISITO: El body de esta ruta DEBE ser Buffer raw (sin JSON     ║
 * ║  parsing). Esto se configura en main.js ANTES de express.json().          ║
 * ║  Ver services/payment-service/src/main.js, sección de raw body parser.    ║
 * ║                                                                            ║
 * ║  Si el body llega como objeto JavaScript (ya parseado), la firma          ║
 * ║  no coincidirá y TODOS los webhooks serán rechazados con 400.             ║
 * ╚════════════════════════════════════════════════════════════════════════════╝
 *
 * Eventos manejados:
 *   • invoice.paid                     → Renovar/activar suscripción
 *   • invoice.payment_failed           → Marcar como past_due
 *   • customer.subscription.deleted    → Cancelar suscripción
 *   • customer.subscription.updated    → Sincronizar cambios de plan
 *   • charge.failed                    → Log de cargo fallido (tarjeta rechazada)
 *
 * Idempotencia:
 *   Stripe puede entregar el mismo evento múltiples veces (garantía at-least-once).
 *   Cada evento tiene un ID único (evt_xxxxxxxx). Verificamos si ese ID ya fue
 *   procesado antes de aplicar cambios a la DB.
 */

'use strict';

const { getStripeClient }        = require('../config/stripe');
const env                        = require('../config/environment');
const subscriptionModel          = require('../models/subscriptionModel');
const { createServiceLogger }    = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:webhook');

// ─────────────────────────────────────────────────────────────────────────────
// HANDLER PRINCIPAL: POST /api/v1/webhooks/stripe
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Recibe y procesa eventos de Stripe.
 *
 * Flujo:
 *   1. Verificar firma Stripe (autenticidad del evento)
 *   2. Verificar idempotencia (evitar procesar el mismo evento dos veces)
 *   3. Despachar al handler específico del tipo de evento
 *   4. Responder 200 a Stripe SIEMPRE (incluso si hay error interno)
 *      → Si respondemos 4xx/5xx, Stripe reintentará el evento hasta 72h
 *      → Solo respondemos 400 si la firma es inválida (evento falso)
 */
async function handleStripeWebhook(req, res) {
  const stripe    = getStripeClient();
  const signature = req.headers['stripe-signature'];

  // ── PASO 1: Verificar firma ───────────────────────────────────────────────
  // req.rawBody es el Buffer guardado por express.raw() en main.js
  // NUNCA usar req.body aquí — ya sería un objeto JS y la firma no coincidiría
  if (!signature) {
    logger.warn('Webhook recibido sin header stripe-signature', { event: 'WEBHOOK_NO_SIGNATURE' });
    return res.status(400).json({ error: 'Missing stripe-signature header.' });
  }

  if (!req.rawBody) {
    logger.error('req.rawBody no disponible — el body parser JSON se aplicó antes del raw parser', {
      event: 'WEBHOOK_CONFIG_ERROR',
    });
    return res.status(500).json({ error: 'Internal configuration error.' });
  }

  let stripeEvent;
  try {
    // constructEvent lanza SignatureVerificationError si la firma es inválida.
    // La tolerancia de tiempo es 300s por defecto (protege contra replay attacks).
    stripeEvent = stripe.webhooks.constructEvent(
      req.rawBody,
      signature,
      env.STRIPE_WEBHOOK_SECRET
    );
  } catch (err) {
    logger.warn('Verificación de firma de Stripe fallida', {
      event:  'WEBHOOK_SIGNATURE_INVALID',
      error:  err.message,
      // No loguear el body ni la firma completa (seguridad)
    });
    // Solo 400 cuando la firma es inválida (evento potencialmente malicioso)
    return res.status(400).json({ error: `Webhook signature verification failed: ${err.message}` });
  }

  const { id: eventId, type: eventType } = stripeEvent;

  logger.info('Evento de Stripe recibido', { eventId, eventType });

  // ── PASO 2: Verificar idempotencia ────────────────────────────────────────
  try {
    const alreadyProcessed = await subscriptionModel.isEventAlreadyProcessed(eventId);
    if (alreadyProcessed) {
      logger.info('Evento ya procesado anteriormente, omitiendo', { eventId, eventType });
      // Responder 200 para que Stripe no reintente (ya lo procesamos)
      return res.status(200).json({ received: true, status: 'already_processed' });
    }
  } catch (dbError) {
    // Si falla la verificación de idempotencia, procesamos de todas formas
    // (es mejor procesar un duplicado que perder un pago legítimo)
    logger.error('Error verificando idempotencia, procesando de todas formas', {
      eventId, error: dbError.message,
    });
  }

  // ── PASO 3: Despachar al handler del tipo de evento ───────────────────────
  try {
    switch (eventType) {

      case 'invoice.paid':
        await handleInvoicePaid(stripeEvent);
        break;

      case 'invoice.payment_failed':
        await handleInvoicePaymentFailed(stripeEvent);
        break;

      case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(stripeEvent);
        break;

      case 'customer.subscription.updated':
        await handleSubscriptionUpdated(stripeEvent);
        break;

      case 'charge.failed':
        await handleChargeFailed(stripeEvent);
        break;

      default:
        // Evento no manejado — loguear y responder 200 (Stripe no reintentará)
        logger.info('Evento de Stripe no manejado, omitiendo', { eventId, eventType });
    }

    // ── PASO 4: Responder 200 a Stripe ────────────────────────────────────
    return res.status(200).json({ received: true, eventId, eventType });

  } catch (handlerError) {
    // Si el handler falla por error interno, logueamos pero respondemos 200.
    // Si respondemos 5xx, Stripe reintentará hasta 72h (puede causar duplicados).
    // La idempotencia nos protege si el evento se reintenta después de corregir el bug.
    logger.error('Error procesando evento de Stripe', {
      eventId,
      eventType,
      error:  handlerError.message,
      stack:  handlerError.stack,
    });

    // En desarrollo, devolver el error para debugging; en producción, siempre 200
    if (!env.IS_PRODUCTION) {
      return res.status(500).json({ error: handlerError.message, eventId });
    }

    return res.status(200).json({
      received: true,
      eventId,
      status:   'processing_error_logged',
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS ESPECÍFICOS POR TIPO DE EVENTO
// ─────────────────────────────────────────────────────────────────────────────

/**
 * invoice.paid — Pago exitoso (nuevo o renovación).
 *
 * Este evento se dispara:
 *   • Cuando se crea una nueva suscripción y se cobra el primer mes
 *   • Cada vez que se renueva automáticamente (mensual/anual)
 *
 * La suscripción ya existe en nuestra DB (fue creada al procesar
 * checkout.session.completed o payment_intent.succeeded).
 */
async function handleInvoicePaid(event) {
  const invoice        = event.data.object;
  const subscriptionId = invoice.subscription;
  const customerId     = invoice.customer;

  if (!subscriptionId) {
    // Factura de pago único (no suscripción), no aplica
    logger.info('invoice.paid sin subscription_id (pago único), omitiendo', {
      invoiceId: invoice.id, customerId,
    });
    return;
  }

  // Obtener detalles completos de la suscripción desde Stripe para conocer
  // el período de facturación (current_period_end = fecha de próximo cobro)
  const stripe       = getStripeClient();
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);

  // Calcular duración del plan en días (del período de Stripe)
  const periodStart    = new Date(subscription.current_period_start * 1000);
  const periodEnd      = new Date(subscription.current_period_end   * 1000);
  const duracionDias   = Math.round((periodEnd - periodStart) / (1000 * 60 * 60 * 24));

  const proximoPagoEn = periodEnd.toISOString();

  // Buscar suscripción en nuestra DB
  const localSub = await subscriptionModel.findByStripeSubscriptionId(subscriptionId);

  if (!localSub) {
    // La suscripción no existe localmente — puede pasar si el usuario se registró
    // directamente en el Dashboard de Stripe (edge case).
    // La creamos desde los datos del evento.
    logger.warn('Suscripción de Stripe no encontrada localmente, creando', {
      subscriptionId, customerId,
    });
    await subscriptionModel.create({
      stripe_customer_id:     customerId,
      stripe_subscription_id: subscriptionId,
      plan_nombre:            subscription.items.data[0]?.price?.nickname || 'Plan Stripe',
      plan_duracion_dias:     duracionDias,
      monto:                  invoice.amount_paid / 100, // Stripe maneja centavos
      moneda:                 invoice.currency.toUpperCase(),
      metodo_pago:            'stripe',
      estado:                 'active',
      valido_desde:           periodStart.toISOString(),
      valido_hasta:           periodEnd.toISOString(),
      ultimo_pago_en:         new Date().toISOString(),
      proximo_pago_en:        proximoPagoEn,
      stripe_event_id_ultimo: event.id,
    });
    return;
  }

  // Actualizar suscripción existente
  await subscriptionModel.activateAfterPayment({
    stripeSubscriptionId: subscriptionId,
    stripeEventId:        event.id,
    proximoPagoEn,
    duracionDias,
  });

  logger.info('invoice.paid procesado', {
    subscriptionId,
    customerId,
    duracionDias,
    proximoPagoEn,
    monto: invoice.amount_paid / 100,
    moneda: invoice.currency,
  });
}

/**
 * invoice.payment_failed — Cobro fallido (tarjeta rechazada, saldo insuficiente, etc.).
 *
 * Stripe reintentará el cobro automáticamente según la configuración del
 * Smart Retry (normalmente 3-4 intentos en 7-14 días).
 * Si todos los reintentos fallan, Stripe enviará customer.subscription.deleted.
 *
 * NO cancelamos la suscripción aquí — la marcamos como 'past_due'.
 * El acceso al gimnasio aún puede estar activo hasta que valido_hasta expire.
 */
async function handleInvoicePaymentFailed(event) {
  const invoice        = event.data.object;
  const subscriptionId = invoice.subscription;

  if (!subscriptionId) return;

  const failureReason = invoice.last_payment_error?.message || 'Cargo fallido';

  try {
    await subscriptionModel.markPaymentFailed({
      stripeSubscriptionId: subscriptionId,
      stripeEventId:        event.id,
      failureReason,
    });
  } catch (err) {
    // Si la suscripción no existe localmente, no es un error crítico
    if (err.code === 'PGRST116') {
      logger.warn('invoice.payment_failed para suscripción no encontrada localmente', {
        subscriptionId, eventId: event.id,
      });
      return;
    }
    throw err;
  }

  logger.warn('Pago fallido registrado', {
    subscriptionId,
    failureReason,
    nextAttempt: invoice.next_payment_attempt
      ? new Date(invoice.next_payment_attempt * 1000).toISOString()
      : 'No hay próximo intento',
  });
}

/**
 * customer.subscription.deleted — Suscripción cancelada definitivamente.
 *
 * Este evento se dispara cuando:
 *   • El usuario cancela desde el Portal de Clientes de Stripe
 *   • Todos los reintentos de cobro fallaron
 *   • Se cancela manualmente desde el Dashboard de Stripe
 *   • Se llama a stripe.subscriptions.cancel() desde el código
 *
 * A partir de este momento, el acceso debe revocarse cuando valido_hasta expire.
 * NO revocar acceso inmediatamente — el período pagado sigue siendo válido.
 */
async function handleSubscriptionDeleted(event) {
  const subscription   = event.data.object;
  const subscriptionId = subscription.id;

  // Determinar razón de cancelación de Stripe
  const cancellationDetails = subscription.cancellation_details;
  let razon = 'stripe_cancelled';
  if (cancellationDetails?.reason) {
    razon = `stripe_${cancellationDetails.reason}`;
  }
  if (subscription.cancel_at_period_end) {
    razon = 'cancelled_at_period_end';
  }

  try {
    await subscriptionModel.cancelSubscription({
      stripeSubscriptionId: subscriptionId,
      stripeEventId:        event.id,
      razon,
    });
  } catch (err) {
    if (err.code === 'PGRST116') {
      logger.warn('customer.subscription.deleted para suscripción no encontrada localmente', {
        subscriptionId, eventId: event.id,
      });
      return;
    }
    throw err;
  }

  logger.info('customer.subscription.deleted procesado', { subscriptionId, razon });
}

/**
 * customer.subscription.updated — Plan, precio o estado cambiaron en Stripe.
 *
 * Sincroniza cambios de plan (upgrade/downgrade) y actualizaciones de estado.
 * Solo se actualiza si hay cambios relevantes.
 */
async function handleSubscriptionUpdated(event) {
  const subscription   = event.data.object;
  const subscriptionId = subscription.id;

  // Solo procesar si el status de Stripe es 'active' (ignorar pending, trialing, etc.)
  if (subscription.status !== 'active') {
    logger.info('customer.subscription.updated con status no-active, omitiendo', {
      subscriptionId, status: subscription.status,
    });
    return;
  }

  // Sincronizar período actual
  const periodEnd = new Date(subscription.current_period_end * 1000);
  await subscriptionModel.activateAfterPayment({
    stripeSubscriptionId: subscriptionId,
    stripeEventId:        event.id,
    proximoPagoEn:        periodEnd.toISOString(),
    duracionDias:         30, // Mantener duración estándar
  });

  logger.info('customer.subscription.updated procesado', { subscriptionId });
}

/**
 * charge.failed — Un cargo específico fue rechazado.
 *
 * Diferencia con invoice.payment_failed:
 *   • charge.failed puede referirse a una carga one-time (sin suscripción)
 *   • Si está vinculado a una suscripción, invoice.payment_failed también se dispara
 *
 * Aquí solo logueamos para auditoría (el modelo de suscripción ya se actualiza
 * vía invoice.payment_failed si aplica).
 */
async function handleChargeFailed(event) {
  const charge = event.data.object;

  logger.warn('Cargo rechazado', {
    event:          'CHARGE_FAILED',
    chargeId:       charge.id,
    customerId:     charge.customer,
    amount:         charge.amount / 100,
    currency:       charge.currency,
    failureCode:    charge.failure_code,
    failureMessage: charge.failure_message,
    // No loguear datos de tarjeta (Stripe no los expone en el evento)
  });

  // Si hay una suscripción vinculada, invoice.payment_failed habrá sido disparado también.
  // No duplicamos la actualización de la DB aquí.
}

module.exports = { handleStripeWebhook };
