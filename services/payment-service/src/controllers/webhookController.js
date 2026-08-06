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
 *   • checkout.session.completed       → Contabilizar canje de cupón (offer_code)
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

const { createClient }           = require('@supabase/supabase-js');
const { getStripeClient }        = require('../config/stripe');
const env                        = require('../config/environment');
const subscriptionModel          = require('../models/subscriptionModel');
const offerModel                 = require('../models/offerModel');
const paymentHistoryModel        = require('../models/paymentHistoryModel');
const { notifyBiometricSync,
        notifyBiometricDelete }  = require('../services/biometricNotificationService');
const { createServiceLogger }    = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:webhook');

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Leer pin_terminal del usuario desde auth_service_db
// El payment-service usa service_role_key, lo que le permite acceder a cualquier
// schema de la misma instancia de Supabase (necesario para cruzar dominios de forma
// controlada en este caso único de sincronización biométrica).
// ─────────────────────────────────────────────────────────────────────────────

let _authDbClient = null;
function getAuthDbClient() {
  if (_authDbClient) return _authDbClient;
  _authDbClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: 'auth_service_db' },
    global: { headers: { 'x-app-name': 'gympro-payment-service-auth-reader' } },
  });
  return _authDbClient;
}

/**
 * Obtiene o auto-asigna el pin_terminal de un usuario para la terminal ZKTeco.
 * Si el usuario aún no tiene PIN, invoca la función SQL assign_pin_terminal() que
 * genera uno atómicamente desde la secuencia.
 *
 * @param {string} usuarioId - UUID del usuario
 * @returns {Promise<{id, nombre, pin_terminal}|null>}
 */
async function getUserBiometricInfo(usuarioId) {
  if (!usuarioId) return null;
  try {
    const db = getAuthDbClient();

    // Intentar obtener PIN existente
    const { data, error } = await db
      .from('usuarios')
      .select('id, nombre, apellido_paterno, pin_terminal')
      .eq('id', usuarioId)
      .is('eliminado_en', null)
      .limit(1)
      .single();

    if (error && error.code !== 'PGRST116') {
      logger.error('Error leyendo usuario desde auth_service_db', { usuarioId, error: error.message });
      return null;
    }
    if (!data) return null;

    // Si aún no tiene PIN, auto-asignar via función SQL atómica
    if (!data.pin_terminal) {
      const { data: pin, error: pinError } = await db.rpc('assign_pin_terminal', {
        p_usuario_id: usuarioId,
      });
      if (pinError) {
        logger.error('Error auto-asignando pin_terminal', { usuarioId, error: pinError.message });
        return { ...data, pin_terminal: null };
      }
      data.pin_terminal = pin;
      logger.info('pin_terminal auto-asignado durante webhook de Stripe', { usuarioId, pin });
    }

    return data;
  } catch (err) {
    logger.error('Excepción en getUserBiometricInfo', { usuarioId, error: err.message });
    return null;
  }
}

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

  // ── PASO 2: Reclamo ATÓMICO de idempotencia ───────────────────────────────
  // INSERT del event_id en el ledger (PK). El primero gana; una entrega duplicada
  // o concurrente del mismo evento choca con la PK y se descarta sin reprocesar.
  let claim;
  try {
    claim = await subscriptionModel.claimWebhookEvent(eventId, eventType);
  } catch (dbError) {
    // Fail-closed: sin garantía de idempotencia NO procesamos. Pedimos reintento
    // a Stripe (5xx) en lugar de arriesgar un doble procesamiento financiero.
    logger.error('Ledger de idempotencia no disponible; se solicita reintento a Stripe', {
      eventId, error: dbError.message,
    });
    return res.status(503).json({ error: 'Idempotency store unavailable. Please retry.' });
  }

  if (!claim.claimed) {
    logger.info('Evento duplicado/concurrente ya reclamado, omitiendo', { eventId, eventType });
    return res.status(200).json({ received: true, status: 'already_processed' });
  }

  // ── PASO 3: Despachar al handler del tipo de evento ───────────────────────
  try {
    switch (eventType) {

      case 'checkout.session.completed':
        await handleCheckoutCompleted(stripeEvent);
        break;

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
    // El handler falló: LIBERAMOS el claim de idempotencia para que el reintento
    // automático de Stripe pueda reprocesar el evento (no perder una activación
    // legítima de pago). Respondemos 5xx para disparar ese reintento.
    logger.error('Error procesando evento de Stripe; se libera claim para reintento', {
      eventId,
      eventType,
      error:  handlerError.message,
      stack:  handlerError.stack,
    });

    await subscriptionModel.releaseWebhookEvent(eventId);

    return res.status(500).json({
      received: false,
      eventId,
      status:   'processing_error_will_retry',
      ...(!env.IS_PRODUCTION && { error: handlerError.message }),
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HANDLERS ESPECÍFICOS POR TIPO DE EVENTO
// ─────────────────────────────────────────────────────────────────────────────

/**
 * checkout.session.completed — El checkout finalizó con éxito.
 *
 * Si la sesión llevaba un cupón (lo registramos en metadata.offer_code al crear
 * la sesión), contabilizamos el canje incrementando ATÓMICAMENTE `usos` en la
 * tabla ofertas. Se ejecuta bajo service_role (offerModel → RPC SECURITY DEFINER),
 * saltando el RLS deny-all de la tabla.
 *
 * Idempotencia: este handler corre bajo el claim atómico del event_id, por lo que
 * cada checkout.session.completed se procesa una sola vez → un único incremento.
 */
/** Normaliza un campo que puede venir como string (id) o como objeto expandido. */
function idOf(v) {
  return v && typeof v === 'object' ? v.id : (v || null);
}

/**
 * Extrae el ID de suscripción de un invoice cubriendo las distintas ubicaciones
 * según la versión de la API de Stripe. En 2024-11-20.acacia+ `invoice.subscription`
 * puede venir null y el dato vive en `invoice.parent.subscription_details.subscription`
 * o a nivel de línea. Antes, con invoice.subscription null, el pago se ignoraba
 * como "pago único" y la membresía NUNCA se activaba.
 */
function resolveInvoiceSubscriptionId(invoice) {
  return idOf(
    invoice.subscription ||
    invoice.parent?.subscription_details?.subscription ||
    invoice.lines?.data?.find((l) => l.subscription)?.subscription ||
    invoice.lines?.data?.[0]?.parent?.subscription_item_details?.subscription ||
    null,
  );
}

/**
 * Resuelve el período de facturación. En la API nueva `current_period_start/end`
 * se movieron del objeto suscripción al ITEM (`items.data[0]`). Antes leerlos del
 * nivel raíz daba `undefined` → `new Date(undefined*1000)` → "Invalid time value".
 */
function resolveSubscriptionPeriod(subscription) {
  const item = subscription.items?.data?.[0];
  const startUnix = subscription.current_period_start ?? item?.current_period_start;
  const endUnix   = subscription.current_period_end   ?? item?.current_period_end;
  const periodStart = startUnix ? new Date(startUnix * 1000) : new Date();
  const periodEnd   = endUnix   ? new Date(endUnix   * 1000) : null;
  const duracionDias = periodEnd
    ? Math.max(1, Math.round((periodEnd - periodStart) / (1000 * 60 * 60 * 24)))
    : 30;
  return { periodStart, periodEnd, duracionDias };
}

async function handleCheckoutCompleted(event) {
  const session   = event.data.object;
  const offerCode = session.metadata?.offer_code;

  // 1) Canje de cupón (si la sesión llevaba offer_code).
  if (offerCode) {
    const nuevosUsos = await offerModel.incrementOfferUsage(offerCode);
    if (nuevosUsos == null) {
      logger.warn('checkout.session.completed: offer_code no encontrado al canjear', {
        sessionId: session.id, offerCode,
      });
    } else {
      logger.info('Canje de cupón contabilizado', {
        sessionId: session.id, offerCode, nuevosUsos,
      });
    }
  }

  // 2) ACTIVACIÓN INMEDIATA de la membresía. Este evento llega en cuanto el pago
  //    se confirma; antes la activación dependía SOLO de invoice.paid, que puede
  //    retrasarse o no estar habilitado en el endpoint del webhook → la app
  //    quedaba "sin membresía" pese a haber pagado. Activamos aquí también.
  if (session.mode === 'subscription' && session.subscription) {
    try {
      const usuarioId = await activateSubscriptionFromStripe(session.subscription, {
        eventId:        event.id,
        customerId:     session.customer,
        amountTotal:    session.amount_total != null ? session.amount_total / 100 : null,
        currency:       session.currency,
        fallbackUserId: session.metadata?.gympro_user_id || null,
      });
      logger.info('checkout.session.completed: membresía activada', {
        sessionId: session.id, subscriptionId: session.subscription, usuarioId,
      });
    } catch (err) {
      logger.error('checkout.session.completed: fallo activando la membresía', {
        sessionId: session.id, subscriptionId: session.subscription, error: err.message,
      });
    }
  }
}

/**
 * Crea o actualiza (a estado 'active') la fila de suscripción local a partir de
 * una suscripción de Stripe. Reutilizado por checkout.session.completed e
 * invoice.paid. Idempotente: si ya existe la fila (por stripe_subscription_id) la
 * actualiza; si no, la crea. El usuario se liga vía metadata.gympro_user_id.
 */
async function activateSubscriptionFromStripe(subscriptionId, opts = {}) {
  const { eventId, customerId, amountTotal, currency, fallbackUserId } = opts;
  const stripe       = getStripeClient();
  const subscription = await stripe.subscriptions.retrieve(subscriptionId);

  const usuarioId    = subscription.metadata?.gympro_user_id || fallbackUserId || null;
  const { periodStart, periodEnd, duracionDias } = resolveSubscriptionPeriod(subscription);
  const proximoPagoEn = (periodEnd || periodStart).toISOString();
  const precio = amountTotal != null
    ? amountTotal
    : (subscription.items.data[0]?.price?.unit_amount ?? 0) / 100;
  const moneda = (currency || subscription.currency || 'mxn').toUpperCase();

  const localSub = await subscriptionModel.findByStripeSubscriptionId(subscriptionId);

  if (!localSub) {
    await subscriptionModel.create({
      usuario_id:             usuarioId,
      stripe_customer_id:     customerId || subscription.customer,
      stripe_subscription_id: subscriptionId,
      plan_nombre:            subscription.items.data[0]?.price?.nickname || 'Plan Stripe',
      plan_precio:            precio,
      plan_duracion_dias:     duracionDias,
      monto:                  precio,
      moneda,
      metodo_pago:            'stripe',
      estado:                 'active',
      valido_desde:           periodStart.toISOString(),
      valido_hasta:           (periodEnd || periodStart).toISOString(),
      ultimo_pago_en:         new Date().toISOString(),
      proximo_pago_en:        proximoPagoEn,
      stripe_event_id_ultimo: eventId,
    });
  } else {
    await subscriptionModel.activateAfterPayment({
      stripeSubscriptionId: subscriptionId,
      stripeEventId:        eventId,
      proximoPagoEn,
      duracionDias,
      usuarioId,
    });
  }
  return usuarioId;
}

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
  const subscriptionId = resolveInvoiceSubscriptionId(invoice);
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

  // Período de facturación (robusto a la API nueva: los campos viven en el item).
  const { periodStart, periodEnd, duracionDias } = resolveSubscriptionPeriod(subscription);
  const proximoPagoEn = (periodEnd || periodStart).toISOString();

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
      // ENLACE CON EL USUARIO: sin esto, findActiveByUserId no la encuentra y la
      // app sigue "inactiva". El id viene del metadata que fijamos al crear la
      // sesión (subscription_data.metadata.gympro_user_id).
      usuario_id:             subscription.metadata?.gympro_user_id || null,
      stripe_customer_id:     customerId,
      stripe_subscription_id: subscriptionId,
      plan_nombre:            subscription.items.data[0]?.price?.nickname || 'Plan Stripe',
      plan_precio:            invoice.amount_paid / 100, // columna NOT NULL (precio del plan)
      plan_duracion_dias:     duracionDias,
      monto:                  invoice.amount_paid / 100, // Stripe maneja centavos
      moneda:                 invoice.currency.toUpperCase(),
      metodo_pago:            'stripe',
      estado:                 'active',
      valido_desde:           periodStart.toISOString(),
      valido_hasta:           (periodEnd || periodStart).toISOString(),
      ultimo_pago_en:         new Date().toISOString(),
      proximo_pago_en:        proximoPagoEn,
      stripe_event_id_ultimo: event.id,
    });
    return;
  }

  // Actualizar suscripción existente (y RELLENAR usuario_id si quedó huérfana en
  // un pago anterior — así deja de aparecer "inactivo" en la app).
  await subscriptionModel.activateAfterPayment({
    stripeSubscriptionId: subscriptionId,
    stripeEventId:        event.id,
    proximoPagoEn,
    duracionDias,
    usuarioId:            subscription.metadata?.gympro_user_id || null,
  });

  logger.info('invoice.paid procesado', {
    subscriptionId,
    customerId,
    duracionDias,
    proximoPagoEn,
    monto: invoice.amount_paid / 100,
    moneda: invoice.currency,
  });

  // ── ASIENTO EN EL LEDGER DE INGRESOS (historial_pagos) ────────────────────
  // Best-effort: la suscripción YA quedó activada arriba; si el asiento falla no
  // revertimos ese estado. Idempotente por stripe_event_id (índice único).
  const montoPagado = (invoice.amount_paid || 0) / 100;
  if (montoPagado > 0 && localSub?.usuario_id) {
    try {
      await paymentHistoryModel.recordOnlinePayment({
        usuarioId:        localSub.usuario_id,
        suscripcionId:    localSub.id,
        monto:            montoPagado,
        moneda:           invoice.currency ? invoice.currency.toUpperCase() : 'MXN',
        planNombre:       subscription.items.data[0]?.price?.nickname || 'Plan Stripe',
        planDuracionDias: duracionDias,
        periodoDesde:     periodStart.toISOString(),
        periodoHasta:     (periodEnd || periodStart).toISOString(),
        stripeEventId:    event.id,
        numeroRecibo:     invoice.number || invoice.id,
      });
    } catch (e) {
      logger.warn('No se pudo asentar el pago online en historial_pagos', {
        eventId: event.id, error: e.message,
      });
    }
  }

  // ── SINCRONIZACIÓN BIOMÉTRICA ZKTECO (fire-and-forget) ───────────────────
  // Obtener el usuario_id de la suscripción local para leer su pin_terminal
  const updatedSub = await subscriptionModel.findByStripeSubscriptionId(subscriptionId);
  if (updatedSub?.usuario_id) {
    const userInfo = await getUserBiometricInfo(updatedSub.usuario_id);
    if (userInfo?.pin_terminal) {
      const nombreCompleto = [
        userInfo.nombre,
        userInfo.apellido_paterno,
      ].filter(Boolean).join(' ');
      // Llamada asíncrona sin await — no bloquea el webhook de Stripe
      notifyBiometricSync(
        updatedSub.usuario_id,
        userInfo.pin_terminal,
        nombreCompleto,
      ).catch((e) => logger.error('Error async biometric sync', { error: e.message }));
    } else {
      logger.warn('invoice.paid: usuario sin pin_terminal, sync ZKTeco omitido', {
        usuarioId: updatedSub.usuario_id,
      });
    }
  }
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
 * REVOCACIÓN FACIAL: la retira el cron processExpiredFacialRevocation en
 * growthRetentionWorker el día que valido_hasta queda en el pasado
 * (grace period = 0), NO este evento. Aquí igualmente disparamos
 * notifyBiometricDelete como red de seguridad: si el cron ya revocó, el
 * DELETE al terminal es un no-op inocuo (borrar un usuario ya ausente).
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

  // ── REVOCACIÓN BIOMÉTRICA ZKTECO (fire-and-forget) ────────────────────────
  // Buscar la suscripción cancelada para obtener usuario_id y su pin_terminal
  const cancelledSub = await subscriptionModel.findByStripeSubscriptionId(subscriptionId)
    .catch(() => null);
  if (cancelledSub?.usuario_id) {
    const userInfo = await getUserBiometricInfo(cancelledSub.usuario_id);
    if (userInfo?.pin_terminal) {
      notifyBiometricDelete(
        cancelledSub.usuario_id,
        userInfo.pin_terminal,
      ).catch((e) => logger.error('Error async biometric delete', { error: e.message }));
    }
  }
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

  // Sincronizar período actual. En la API nueva current_period_* vive en el item,
  // no en el nivel raíz → leerlo directo daba "Invalid time value" y tumbaba el
  // handler (por eso subscription.updated devolvía 400 y no activaba).
  const { periodEnd, duracionDias } = resolveSubscriptionPeriod(subscription);
  const proximoPagoEn = (periodEnd || new Date()).toISOString();
  try {
    await subscriptionModel.activateAfterPayment({
      stripeSubscriptionId: subscriptionId,
      stripeEventId:        event.id,
      proximoPagoEn,
      duracionDias:         duracionDias || 30,
      usuarioId:            subscription.metadata?.gympro_user_id || null,
    });
  } catch (err) {
    // Stripe envía subscription.updated e invoice.paid casi simultáneos: si el
    // update llega ANTES de que invoice.paid cree la fila, no existe localmente.
    // No es crítico (invoice.paid la crea) → evitamos el 500 y el reintento.
    if (String(err.message || '').toLowerCase().includes('no encontrada')) {
      logger.warn('subscription.updated: suscripción aún no existe localmente; se omite (la crea invoice.paid)', {
        subscriptionId,
      });
      return;
    }
    throw err;
  }

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
