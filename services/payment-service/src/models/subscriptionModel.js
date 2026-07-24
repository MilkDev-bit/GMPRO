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
      // Re-habilita al usuario para el cron de revocación facial: si había
      // sido revocado por vencimiento y ahora vuelve a pagar, el flag se
      // limpia para que el alta biométrica (invoice.paid → notifyBiometricSync)
      // no quede bloqueada y una futura expiración vuelva a revocar.
      acceso_facial_revocado_en: null,
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
 * Registra un pago en efectivo de forma ATÓMICA e IDEMPOTENTE vía la RPC
 * payment_service_db.registrar_pago_efectivo.
 *
 * La duración del acceso la determina el PLAN (tabla `planes`), no el
 * cliente (fix 2.3). La extensión de `valido_hasta` y el asiento en el
 * ledger ocurren en una sola transacción, con la Idempotency-Key como
 * guard de concurrencia (fix 2.2).
 *
 * @param {object} params
 * @param {string} params.usuarioId
 * @param {string} params.planId             - UUID del plan canónico
 * @param {number} params.montoCobrado       - Monto realmente cobrado (MXN)
 * @param {string} params.metodoPago         - 'cash' | 'card_terminal' | 'transfer'
 * @param {string} params.receptionistaId
 * @param {string} params.idempotencyKey
 * @param {string} params.numeroRecibo       - Folio generado en el servicio
 * @param {string} [params.paseCortesiaCodigo]
 * @param {string} [params.notas]
 * @returns {Promise<{ yaProcesado: boolean, action: string, subscription: object, pago: object }>}
 * @throws  {Error} err.code === 'PLAN_NOT_FOUND' si el plan no existe/está inactivo.
 */
async function registerCashPayment({
  usuarioId,
  planId,
  montoCobrado,
  metodoPago = 'cash',
  receptionistaId,
  idempotencyKey,
  numeroRecibo,
  paseCortesiaCodigo = null,
  notas = null,
}) {
  const db = getSupabaseClient();

  const { data, error } = await db.rpc('registrar_pago_efectivo', {
    p_usuario_id:           usuarioId,
    p_plan_id:              planId,
    p_monto_cobrado:        montoCobrado,
    p_metodo_pago:          metodoPago,
    p_receptionist_id:      receptionistaId,
    p_idempotency_key:      idempotencyKey,
    p_numero_recibo:        numeroRecibo,
    p_pase_cortesia_codigo: paseCortesiaCodigo,
    p_notas:                notas,
  });

  if (error) {
    // La RPC lanza P0002 ('PLAN_NOT_FOUND') si el plan no existe/está inactivo.
    if (error.code === 'P0002' || /PLAN_NOT_FOUND/.test(error.message || '')) {
      const e = new Error('PLAN_NOT_FOUND');
      e.code = 'PLAN_NOT_FOUND';
      throw e;
    }
    logger.error('Error en RPC registrar_pago_efectivo', {
      usuarioId, planId, receptionistaId, code: error.code, error: error.message,
    });
    throw error;
  }

  const result = {
    yaProcesado:  data.ya_procesado === true,
    action:       data.accion,
    subscription: data.suscripcion,
    pago:         data.pago,
  };

  logger.info('Pago efectivo procesado (RPC atómica)', {
    usuarioId,
    action: result.action,
    yaProcesado: result.yaProcesado,
    suscripcionId: result.subscription?.id,
    validoHasta: result.subscription?.valido_hasta,
    receptionistaId,
  });

  return result;
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

// ── ADMIN (panel staff/admin) ────────────────────────────────────────────────
/** Busca una suscripción por su id local. */
async function findById(id) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .select(SAFE_COLUMNS + ', stripe_subscription_id')
    .eq('id', id)
    .limit(1)
    .single();
  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/** Lista suscripciones para el panel, opcionalmente filtradas por estado. */
async function listForAdmin({ estado = null, limit = 200 } = {}) {
  const db = getSupabaseClient();
  let query = db
    .from('suscripciones')
    .select(SAFE_COLUMNS)
    .order('creado_en', { ascending: false })
    .limit(Math.min(limit, 500));
  if (estado) query = query.eq('estado', estado);
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

/** Resumen financiero para el dashboard. `ingresosMes` = MRR de las activas
 *  (proxy recurrente); para caja real del mes, sumar la tabla de pagos. */
async function financeSummary() {
  const db = getSupabaseClient();
  const startMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();

  const countBy = async (apply) => {
    const { count, error } = await apply(
      db.from('suscripciones').select('id', { count: 'exact', head: true }),
    );
    if (error) throw error;
    return count || 0;
  };

  const suscripcionesActivas = await countBy((q) => q.eq('estado', 'active'));
  const suscripcionesPastDue = await countBy((q) => q.eq('estado', 'past_due'));
  const altasMes = await countBy((q) => q.gte('creado_en', startMonth));
  const bajasMes = await countBy((q) => q.eq('estado', 'cancelled').gte('cancelado_en', startMonth));

  const { data: actives, error } = await db
    .from('suscripciones').select('monto, moneda').eq('estado', 'active');
  if (error) throw error;
  const ingresosMes = (actives || []).reduce((a, s) => a + (Number(s.monto) || 0), 0);
  const moneda = actives?.[0]?.moneda || 'MXN';

  return { ingresosMes, moneda, suscripcionesActivas, suscripcionesPastDue, altasMes, bajasMes };
}

/** Cancela una suscripción por id (marca estado y fecha). */
async function cancelById(id) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('suscripciones')
    .update({ estado: 'cancelled', cancelado_en: new Date().toISOString() })
    .eq('id', id)
    .select(SAFE_COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

/** Otorga cortesía/extensión: suma `dias` a valido_hasta (desde hoy o desde el
 *  vencimiento actual, el que sea mayor) y reactiva la suscripción. */
async function extendById(id, dias) {
  const db = getSupabaseClient();
  const { data: sub, error: e1 } = await db
    .from('suscripciones').select('valido_hasta').eq('id', id).limit(1).single();
  if (e1) throw e1;

  const base = Math.max(sub.valido_hasta ? new Date(sub.valido_hasta).getTime() : 0, Date.now());
  const nuevoValidoHasta = new Date(base + dias * 24 * 60 * 60 * 1000).toISOString();

  const { data, error } = await db
    .from('suscripciones')
    .update({ estado: 'active', valido_hasta: nuevoValidoHasta })
    .eq('id', id)
    .select(SAFE_COLUMNS)
    .single();
  if (error) throw error;
  return data;
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
  findById,
  listForAdmin,
  financeSummary,
  cancelById,
  extendById,
};
