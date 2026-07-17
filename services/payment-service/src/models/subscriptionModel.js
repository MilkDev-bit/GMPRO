/**
 * @file services/payment-service/src/models/subscriptionModel.js
 * @description Capa de acceso a datos para payment_service_db.suscripciones.
 *
 * IMPORTANTE SOBRE IDEMPOTENCIA:
 *   Stripe puede entregar el mismo evento de webhook más de una vez.
 *   Por eso, todas las operaciones de actualización usan el stripe_event_id
 *   como guard de idempotencia: si ya se procesó, la query no hace nada.
 *   Adicionalmente guardamos el stripe_event_id en la tabla para detectar duplicados.
 */

'use strict';

const { getSupabaseClient } = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('payment-service:subscriptionModel');

// Columnas seguras (sin exponer datos internos de Stripe al caller innecesariamente)
const SAFE_COLUMNS = [
  'id', 'usuario_id', 'stripe_customer_id', 'stripe_subscription_id',
  'plan_nombre', 'plan_duracion_dias', 'monto', 'moneda',
  'metodo_pago', 'estado', 'valido_desde', 'valido_hasta',
  'ultimo_pago_en', 'proximo_pago_en', 'cancelado_en',
  'creado_en', 'actualizado_en',
].join(', ');

/**
 * Busca la suscripción activa de un usuario.
 *
 * @param {string} usuarioId - UUID del usuario en auth_service_db
 * @returns {Promise<object|null>}
 */
async function findActiveByUserId(usuarioId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select(SAFE_COLUMNS)
    .eq('usuario_id', usuarioId)
    .eq('estado', 'active')
    .order('valido_hasta', { ascending: false })
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/**
 * Busca una suscripción por stripe_subscription_id.
 * Usada en el handler del webhook para localizar la suscripción a actualizar.
 *
 * @param {string} stripeSubscriptionId
 * @returns {Promise<object|null>}
 */
async function findByStripeSubscriptionId(stripeSubscriptionId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select(SAFE_COLUMNS + ', stripe_event_id_ultimo')
    .eq('stripe_subscription_id', stripeSubscriptionId)
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/**
 * Busca una suscripción por stripe_customer_id.
 *
 * @param {string} stripeCustomerId
 * @returns {Promise<object|null>}
 */
async function findByStripeCustomerId(stripeCustomerId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select(SAFE_COLUMNS)
    .eq('stripe_customer_id', stripeCustomerId)
    .order('creado_en', { ascending: false })
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/**
 * Verifica si un stripe_event_id ya fue procesado (idempotencia).
 *
 * @param {string} stripeEventId
 * @returns {Promise<boolean>}
 */
async function isEventAlreadyProcessed(stripeEventId) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select('id')
    .eq('stripe_event_id_ultimo', stripeEventId)
    .limit(1)
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return !!data;
}

/**
 * Crea una nueva suscripción.
 *
 * @param {object} subscriptionData
 * @returns {Promise<object>}
 */
async function create(subscriptionData) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .insert(subscriptionData)
    .select(SAFE_COLUMNS)
    .single();

  if (error) {
    logger.error('Error creando suscripción', { error: error.message });
    throw error;
  }
  logger.info('Suscripción creada', { id: data.id, userId: data.usuario_id });
  return data;
}

/**
 * Activa (o renueva) una suscripción tras un pago exitoso.
 * Calcula valido_hasta sumando plan_duracion_dias a la fecha actual.
 *
 * @param {string}  stripeSubscriptionId
 * @param {string}  stripeEventId          - Para idempotencia
 * @param {string}  proximoPagoEn          - Timestamp del próximo pago (de Stripe)
 * @param {number}  [duracionDias=30]      - Días de vigencia del plan
 * @returns {Promise<object>} Suscripción actualizada
 */
async function activateAfterPayment({
  stripeSubscriptionId,
  stripeEventId,
  proximoPagoEn = null,
  duracionDias  = 30,
}) {
  const db        = getSupabaseClient();
  const ahora     = new Date();
  const validoHasta = new Date(ahora);
  validoHasta.setDate(validoHasta.getDate() + duracionDias);

  const { data, error } = await db
    .from('suscripciones')
    .update({
      estado:                 'active',
      valido_desde:           ahora.toISOString(),
      valido_hasta:           validoHasta.toISOString(),
      ultimo_pago_en:         ahora.toISOString(),
      proximo_pago_en:        proximoPagoEn,
      cancelado_en:           null,        // Limpiar si había sido cancelada
      stripe_event_id_ultimo: stripeEventId,
      actualizado_en:         ahora.toISOString(),
    })
    .eq('stripe_subscription_id', stripeSubscriptionId)
    .select(SAFE_COLUMNS)
    .single();

  if (error) {
    logger.error('Error activando suscripción', {
      stripeSubscriptionId, stripeEventId, error: error.message,
    });
    throw error;
  }

  logger.info('Suscripción activada/renovada', {
    id:           data.id,
    userId:       data.usuario_id,
    validoHasta:  validoHasta.toISOString(),
    stripeEventId,
  });

  return data;
}

/**
 * Cancela una suscripción (evento customer.subscription.deleted de Stripe).
 *
 * @param {string} stripeSubscriptionId
 * @param {string} stripeEventId
 * @param {string} [razon='stripe_cancelled'] - Razón de cancelación
 * @returns {Promise<object>}
 */
async function cancelSubscription({ stripeSubscriptionId, stripeEventId, razon = 'stripe_cancelled' }) {
  const db    = getSupabaseClient();
  const ahora = new Date();

  const { data, error } = await db
    .from('suscripciones')
    .update({
      estado:                 'cancelled',
      cancelado_en:           ahora.toISOString(),
      razon_cancelacion:      razon,
      stripe_event_id_ultimo: stripeEventId,
      actualizado_en:         ahora.toISOString(),
    })
    .eq('stripe_subscription_id', stripeSubscriptionId)
    .select(SAFE_COLUMNS)
    .single();

  if (error) throw error;

  logger.info('Suscripción cancelada', {
    id: data.id, userId: data.usuario_id, razon, stripeEventId,
  });
  return data;
}

/**
 * Marca una suscripción con pago fallido.
 * No cancela la suscripción — Stripe reintentará el cobro automáticamente.
 *
 * @param {string} stripeSubscriptionId
 * @param {string} stripeEventId
 * @param {string} [failureReason]
 * @returns {Promise<object>}
 */
async function markPaymentFailed({ stripeSubscriptionId, stripeEventId, failureReason = null }) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('suscripciones')
    .update({
      estado:                 'past_due',   // Pago vencido, aún no cancelada
      razon_fallo_pago:       failureReason,
      stripe_event_id_ultimo: stripeEventId,
      actualizado_en:         new Date().toISOString(),
    })
    .eq('stripe_subscription_id', stripeSubscriptionId)
    .select(SAFE_COLUMNS)
    .single();

  if (error) throw error;

  logger.warn('Pago fallido registrado', {
    id: data.id, userId: data.usuario_id, failureReason, stripeEventId,
  });
  return data;
}

/**
 * Registra un pago en efectivo creando o renovando una suscripción.
 * El campo stripe_subscription_id queda null (no hay suscripción en Stripe).
 *
 * @param {object} params
 * @param {string} params.usuarioId
 * @param {string} params.planNombre
 * @param {number} params.planDuracionDias  - Días de vigencia
 * @param {number} params.monto             - Monto en pesos MXN
 * @param {string} params.receptionistaId   - ID del recepcionista que registra
 * @param {string} [params.notas]           - Notas adicionales del recepcionista
 * @returns {Promise<object>} Suscripción creada/actualizada
 */
async function registerCashPayment({
  usuarioId,
  planNombre,
  planDuracionDias = 30,
  monto,
  receptionistaId,
  notas = null,
}) {
  const db          = getSupabaseClient();
  const ahora       = new Date();
  const validoHasta = new Date(ahora);
  validoHasta.setDate(validoHasta.getDate() + planDuracionDias);

  // Verificar si el usuario ya tiene una suscripción activa para renovarla
  const existing = await findActiveByUserId(usuarioId);

  if (existing) {
    // RENOVACIÓN: Si ya tiene suscripción activa, extender desde valido_hasta actual
    // (no desde ahora, para no perder días restantes)
    const baseDate = new Date(existing.valido_hasta) > ahora
      ? new Date(existing.valido_hasta)
      : ahora;
    const nuevaFecha = new Date(baseDate);
    nuevaFecha.setDate(nuevaFecha.getDate() + planDuracionDias);

    const { data, error } = await db
      .from('suscripciones')
      .update({
        plan_nombre:       planNombre,
        plan_duracion_dias: planDuracionDias,
        monto,
        metodo_pago:       'cash',
        estado:            'active',
        valido_hasta:      nuevaFecha.toISOString(),
        ultimo_pago_en:    ahora.toISOString(),
        receptionist_id:   receptionistaId,
        notas_internas:    notas,
        cancelado_en:      null,
        actualizado_en:    ahora.toISOString(),
      })
      .eq('id', existing.id)
      .select(SAFE_COLUMNS)
      .single();

    if (error) throw error;
    logger.info('Suscripción cash renovada', {
      id: data.id, userId: data.usuario_id,
      validoHasta: nuevaFecha.toISOString(), receptionistaId,
    });
    return { subscription: data, action: 'renewed' };
  }

  // NUEVA SUSCRIPCIÓN: El usuario no tiene una activa
  const { data, error } = await db
    .from('suscripciones')
    .insert({
      usuario_id:             usuarioId,
      stripe_customer_id:     null,
      stripe_subscription_id: null,
      plan_nombre:            planNombre,
      plan_duracion_dias:     planDuracionDias,
      monto,
      moneda:                 'MXN',
      metodo_pago:            'cash',
      estado:                 'active',
      valido_desde:           ahora.toISOString(),
      valido_hasta:           validoHasta.toISOString(),
      ultimo_pago_en:         ahora.toISOString(),
      receptionist_id:        receptionistaId,
      notas_internas:         notas,
    })
    .select(SAFE_COLUMNS)
    .single();

  if (error) throw error;
  logger.info('Suscripción cash creada', {
    id: data.id, userId: data.usuario_id,
    validoHasta: validoHasta.toISOString(), receptionistaId,
  });
  return { subscription: data, action: 'created' };
}

/**
 * Obtiene el historial de suscripciones de un usuario.
 *
 * @param {string} usuarioId
 * @param {number} [limit=10]
 * @returns {Promise<object[]>}
 */
async function getHistoryByUserId(usuarioId, limit = 10) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select(SAFE_COLUMNS)
    .eq('usuario_id', usuarioId)
    .order('creado_en', { ascending: false })
    .limit(limit);

  if (error) throw error;
  return data || [];
}

/**
 * Reclama ATÓMICAMENTE un evento de webhook de Stripe para procesarlo una sola vez.
 *
 * FIX DE IDEMPOTENCIA (race at-least-once):
 *   Inserta el event_id en el ledger webhook_events_procesados (PK = event_id).
 *   • Éxito           → { claimed: true }  (este proceso es el dueño; procede a procesar).
 *   • Violación 23505 → { claimed: false } (otra entrega ya lo reclamó → duplicado seguro).
 *   • Otro error      → lanza (fail-closed: sin garantía de idempotencia NO se procesa;
 *                        el caller responde 5xx y Stripe reintenta más tarde).
 *
 * @param {string} eventId
 * @param {string} tipo
 * @returns {Promise<{ claimed: boolean }>}
 */
async function claimWebhookEvent(eventId, tipo) {
  const db = getSupabaseClient();
  const { error } = await db
    .from('webhook_events_procesados')
    .insert({ event_id: eventId, tipo });

  if (error) {
    if (error.code === '23505') return { claimed: false };
    logger.error('Error reclamando evento de webhook (idempotencia)', {
      eventId, code: error.code, error: error.message,
    });
    throw error;
  }
  return { claimed: true };
}

/**
 * Libera un evento previamente reclamado (p. ej. si el handler falló) para que el
 * reintento automático de Stripe pueda reprocesarlo. No lanza.
 *
 * @param {string} eventId
 */
async function releaseWebhookEvent(eventId) {
  try {
    const db = getSupabaseClient();
    await db.from('webhook_events_procesados').delete().eq('event_id', eventId);
  } catch (err) {
    logger.warn('No se pudo liberar el claim de webhook para reintento', { eventId, error: err.message });
  }
}

module.exports = {
  findActiveByUserId,
  findByStripeSubscriptionId,
  findByStripeCustomerId,
  isEventAlreadyProcessed,
  claimWebhookEvent,
  releaseWebhookEvent,
  create,
  activateAfterPayment,
  cancelSubscription,
  markPaymentFailed,
  registerCashPayment,
  getHistoryByUserId,
};
