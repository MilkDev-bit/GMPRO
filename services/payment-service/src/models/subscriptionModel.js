/**
 * @file services/payment-service/src/models/subscriptionModel.js
 * @description Capa de acceso a datos para payment_service_db.suscripciones.
 *
 * Mínimo privilegio (CLD-1): opera vía `pg` con el rol svc_payment (query()),
 * SQL SIEMPRE parametrizado ($1,$2,…) — nunca concatenar valores.
 *
 * IDEMPOTENCIA (Stripe at-least-once): las actualizaciones guardan stripe_event_id
 * y el claim de webhook usa la PK de webhook_events_procesados (23505 = duplicado).
 */

'use strict';

const { query } = require('../config/database');
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

/** Busca la suscripción activa de un usuario. @returns {Promise<object|null>} */
async function findActiveByUserId(usuarioId) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM suscripciones
     WHERE usuario_id = $1 AND estado = 'active'
     ORDER BY valido_hasta DESC LIMIT 1`,
    [usuarioId],
  );
  return rows[0] || null;
}

/** Busca una suscripción por stripe_subscription_id. @returns {Promise<object|null>} */
async function findByStripeSubscriptionId(stripeSubscriptionId) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS}, stripe_event_id_ultimo FROM suscripciones
     WHERE stripe_subscription_id = $1 LIMIT 1`,
    [stripeSubscriptionId],
  );
  return rows[0] || null;
}

/** Busca una suscripción por stripe_customer_id. @returns {Promise<object|null>} */
async function findByStripeCustomerId(stripeCustomerId) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM suscripciones
     WHERE stripe_customer_id = $1
     ORDER BY creado_en DESC LIMIT 1`,
    [stripeCustomerId],
  );
  return rows[0] || null;
}

/** Verifica si un stripe_event_id ya fue procesado (idempotencia). */
async function isEventAlreadyProcessed(stripeEventId) {
  const { rows } = await query(
    `SELECT id FROM suscripciones WHERE stripe_event_id_ultimo = $1 LIMIT 1`,
    [stripeEventId],
  );
  return rows.length > 0;
}

/**
 * Crea una nueva suscripción. `subscriptionData` = objeto columna→valor (claves
 * generadas por el propio servicio; se citan como identificadores).
 * @returns {Promise<object>}
 */
async function create(subscriptionData) {
  const cols = Object.keys(subscriptionData);
  const vals = Object.values(subscriptionData);
  const colList = cols.map((c) => `"${c}"`).join(', ');
  const placeholders = cols.map((_, i) => `$${i + 1}`).join(', ');
  try {
    const { rows } = await query(
      `INSERT INTO suscripciones (${colList}) VALUES (${placeholders}) RETURNING ${SAFE_COLUMNS}`,
      vals,
    );
    const data = rows[0];
    logger.info('Suscripción creada', { id: data.id, userId: data.usuario_id });
    return data;
  } catch (error) {
    logger.error('Error creando suscripción', { error: error.message });
    throw error;
  }
}

/**
 * Activa (o renueva) una suscripción tras un pago exitoso.
 * @returns {Promise<object>} Suscripción actualizada
 */
async function activateAfterPayment({
  stripeSubscriptionId,
  stripeEventId,
  proximoPagoEn = null,
  duracionDias  = 30,
}) {
  const ahora = new Date();
  const validoHasta = new Date(ahora);
  validoHasta.setDate(validoHasta.getDate() + duracionDias);

  try {
    const { rows } = await query(
      `UPDATE suscripciones SET
         estado = 'active',
         valido_desde = $2,
         valido_hasta = $3,
         ultimo_pago_en = $2,
         proximo_pago_en = $4,
         cancelado_en = NULL,
         acceso_facial_revocado_en = NULL,   -- re-habilita el alta biométrica al re-pagar
         stripe_event_id_ultimo = $5,
         actualizado_en = $2
       WHERE stripe_subscription_id = $1
       RETURNING ${SAFE_COLUMNS}`,
      [stripeSubscriptionId, ahora.toISOString(), validoHasta.toISOString(), proximoPagoEn, stripeEventId],
    );
    if (!rows[0]) throw new Error(`Suscripción no encontrada para stripe_subscription_id=${stripeSubscriptionId}`);
    const data = rows[0];
    logger.info('Suscripción activada/renovada', {
      id: data.id, userId: data.usuario_id, validoHasta: validoHasta.toISOString(), stripeEventId,
    });
    return data;
  } catch (error) {
    logger.error('Error activando suscripción', { stripeSubscriptionId, stripeEventId, error: error.message });
    throw error;
  }
}

/** Cancela una suscripción (customer.subscription.deleted). @returns {Promise<object>} */
async function cancelSubscription({ stripeSubscriptionId, stripeEventId, razon = 'stripe_cancelled' }) {
  const ahora = new Date().toISOString();
  const { rows } = await query(
    `UPDATE suscripciones SET
       estado = 'cancelled',
       cancelado_en = $2,
       razon_cancelacion = $3,
       stripe_event_id_ultimo = $4,
       actualizado_en = $2
     WHERE stripe_subscription_id = $1
     RETURNING ${SAFE_COLUMNS}`,
    [stripeSubscriptionId, ahora, razon, stripeEventId],
  );
  if (!rows[0]) throw new Error(`Suscripción no encontrada para stripe_subscription_id=${stripeSubscriptionId}`);
  logger.info('Suscripción cancelada', { id: rows[0].id, userId: rows[0].usuario_id, razon, stripeEventId });
  return rows[0];
}

/** Marca pago fallido (no cancela; Stripe reintenta). @returns {Promise<object>} */
async function markPaymentFailed({ stripeSubscriptionId, stripeEventId, failureReason = null }) {
  const { rows } = await query(
    `UPDATE suscripciones SET
       estado = 'past_due',
       razon_fallo_pago = $3,
       stripe_event_id_ultimo = $2,
       actualizado_en = $4
     WHERE stripe_subscription_id = $1
     RETURNING ${SAFE_COLUMNS}`,
    [stripeSubscriptionId, stripeEventId, failureReason, new Date().toISOString()],
  );
  if (!rows[0]) throw new Error(`Suscripción no encontrada para stripe_subscription_id=${stripeSubscriptionId}`);
  logger.warn('Pago fallido registrado', { id: rows[0].id, userId: rows[0].usuario_id, failureReason, stripeEventId });
  return rows[0];
}

/**
 * Registra un pago en efectivo ATÓMICO e IDEMPOTENTE vía la RPC SECURITY DEFINER
 * payment_service_db.registrar_pago_efectivo (extensión de vigencia + asiento en
 * ledger en una sola transacción; Idempotency-Key como guard).
 * @throws {Error} err.code === 'PLAN_NOT_FOUND' si el plan no existe/está inactivo.
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
  try {
    // Orden posicional de la firma: p_usuario_id, p_plan_id, p_monto_cobrado,
    // p_metodo_pago, p_receptionist_id, p_idempotency_key, p_numero_recibo,
    // p_pase_cortesia_codigo, p_notas.
    const { rows } = await query(
      `SELECT payment_service_db.registrar_pago_efectivo($1,$2,$3,$4,$5,$6,$7,$8,$9) AS result`,
      [usuarioId, planId, montoCobrado, metodoPago, receptionistaId,
       idempotencyKey, numeroRecibo, paseCortesiaCodigo, notas],
    );
    const data = rows[0].result;   // jsonb → objeto { ya_procesado, accion, suscripcion, pago }
    const result = {
      yaProcesado:  data.ya_procesado === true,
      action:       data.accion,
      subscription: data.suscripcion,
      pago:         data.pago,
    };
    logger.info('Pago efectivo procesado (RPC atómica)', {
      usuarioId, action: result.action, yaProcesado: result.yaProcesado,
      suscripcionId: result.subscription?.id, validoHasta: result.subscription?.valido_hasta, receptionistaId,
    });
    return result;
  } catch (error) {
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
}

/** Historial de suscripciones de un usuario. @returns {Promise<object[]>} */
async function getHistoryByUserId(usuarioId, limit = 10) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM suscripciones
     WHERE usuario_id = $1 ORDER BY creado_en DESC LIMIT $2`,
    [usuarioId, limit],
  );
  return rows;
}

/**
 * Reclama ATÓMICAMENTE un evento de webhook (procesar una sola vez).
 *   éxito → { claimed:true } · 23505 → { claimed:false } · otro → lanza (fail-closed).
 */
async function claimWebhookEvent(eventId, tipo) {
  try {
    await query(
      `INSERT INTO webhook_events_procesados (event_id, tipo) VALUES ($1, $2)`,
      [eventId, tipo],
    );
    return { claimed: true };
  } catch (error) {
    if (error.code === '23505') return { claimed: false };
    logger.error('Error reclamando evento de webhook (idempotencia)', {
      eventId, code: error.code, error: error.message,
    });
    throw error;
  }
}

/** Libera un evento reclamado (si el handler falló) para el reintento de Stripe. No lanza. */
async function releaseWebhookEvent(eventId) {
  try {
    await query(`DELETE FROM webhook_events_procesados WHERE event_id = $1`, [eventId]);
  } catch (err) {
    logger.warn('No se pudo liberar el claim de webhook para reintento', { eventId, error: err.message });
  }
}

// ── ADMIN (panel staff/admin) ────────────────────────────────────────────────
/** Busca una suscripción por su id local. */
async function findById(id) {
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS}, stripe_subscription_id FROM suscripciones WHERE id = $1 LIMIT 1`,
    [id],
  );
  return rows[0] || null;
}

/** Lista suscripciones para el panel, opcionalmente filtradas por estado. */
async function listForAdmin({ estado = null, limit = 200 } = {}) {
  const lim = Math.min(limit, 500);
  if (estado) {
    const { rows } = await query(
      `SELECT ${SAFE_COLUMNS} FROM suscripciones WHERE estado = $1
       ORDER BY creado_en DESC LIMIT $2`,
      [estado, lim],
    );
    return rows;
  }
  const { rows } = await query(
    `SELECT ${SAFE_COLUMNS} FROM suscripciones ORDER BY creado_en DESC LIMIT $1`,
    [lim],
  );
  return rows;
}

/** Resumen financiero para el dashboard. `ingresosMes` = MRR de las activas (proxy). */
async function financeSummary() {
  const startMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
  const { rows } = await query(
    `SELECT
       count(*) FILTER (WHERE estado = 'active')                                    AS activas,
       count(*) FILTER (WHERE estado = 'past_due')                                  AS past_due,
       count(*) FILTER (WHERE creado_en >= $1)                                      AS altas_mes,
       count(*) FILTER (WHERE estado = 'cancelled' AND cancelado_en >= $1)          AS bajas_mes,
       COALESCE(SUM(monto) FILTER (WHERE estado = 'active'), 0)                     AS ingresos,
       (array_agg(moneda) FILTER (WHERE estado = 'active'))[1]                      AS moneda
     FROM suscripciones`,
    [startMonth],
  );
  const r = rows[0];
  return {
    ingresosMes:            Number(r.ingresos) || 0,
    moneda:                 r.moneda || 'MXN',
    suscripcionesActivas:   Number(r.activas) || 0,
    suscripcionesPastDue:   Number(r.past_due) || 0,
    altasMes:               Number(r.altas_mes) || 0,
    bajasMes:               Number(r.bajas_mes) || 0,
  };
}

const MES_ABBR = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const monthKeyOf = (iso) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};

/**
 * Serie mensual para el dashboard financiero (últimos `months` meses).
 * El bucketing se hace en JS (se mantiene igual que antes).
 */
async function financeSeries({ months = 12 } = {}) {
  const m = Math.max(1, Math.min(Number(months) || 12, 36));
  const now = new Date();
  const windowStart = new Date(now.getFullYear(), now.getMonth() - (m - 1), 1).toISOString();

  const keys = [];
  const labels = {};
  for (let i = 0; i < m; i++) {
    const d = new Date(now.getFullYear(), now.getMonth() - (m - 1) + i, 1);
    const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    keys.push(k);
    labels[k] = `${MES_ABBR[d.getMonth()]} ${String(d.getFullYear()).slice(2)}`;
  }
  const idx = Object.fromEntries(keys.map((k, i) => [k, i]));

  const ingresos = new Array(m).fill(0);
  const altas = new Array(m).fill(0);
  const bajas = new Array(m).fill(0);

  // Ingresos (ledger presencial + Stripe vía migración 008).
  const { rows: pagos } = await query(
    `SELECT monto, moneda, creado_en FROM historial_pagos
     WHERE estado_pago = 'completed' AND creado_en >= $1`,
    [windowStart],
  );
  let moneda = 'MXN';
  for (const p of pagos) {
    const k = monthKeyOf(p.creado_en);
    if (k in idx) ingresos[idx[k]] += Number(p.monto) || 0;
    if (p.moneda) moneda = p.moneda;
  }

  // Altas.
  const { rows: nuevas } = await query(
    `SELECT creado_en FROM suscripciones WHERE creado_en >= $1`,
    [windowStart],
  );
  for (const s of nuevas) {
    const k = monthKeyOf(s.creado_en);
    if (k in idx) altas[idx[k]] += 1;
  }

  // Bajas.
  const { rows: canceladas } = await query(
    `SELECT cancelado_en FROM suscripciones
     WHERE estado = 'cancelled' AND cancelado_en >= $1`,
    [windowStart],
  );
  for (const s of canceladas) {
    if (!s.cancelado_en) continue;
    const k = monthKeyOf(s.cancelado_en);
    if (k in idx) bajas[idx[k]] += 1;
  }

  return {
    moneda,
    ingresos:   keys.map((k, i) => ({ ym: k, label: labels[k], value: ingresos[i] })),
    altasBajas: keys.map((k, i) => ({ ym: k, label: labels[k], altas: altas[i], bajas: bajas[i] })),
  };
}

/** Cancela una suscripción por id (marca estado y fecha). */
async function cancelById(id) {
  const { rows } = await query(
    `UPDATE suscripciones SET estado = 'cancelled', cancelado_en = $2
     WHERE id = $1 RETURNING ${SAFE_COLUMNS}`,
    [id, new Date().toISOString()],
  );
  if (!rows[0]) throw new Error(`Suscripción no encontrada: ${id}`);
  return rows[0];
}

/** Otorga cortesía/extensión: suma `dias` a valido_hasta (desde hoy o el vencimiento, el mayor). */
async function extendById(id, dias) {
  const { rows: subRows } = await query(
    `SELECT valido_hasta FROM suscripciones WHERE id = $1 LIMIT 1`,
    [id],
  );
  if (!subRows[0]) throw new Error(`Suscripción no encontrada: ${id}`);
  const sub = subRows[0];

  const base = Math.max(sub.valido_hasta ? new Date(sub.valido_hasta).getTime() : 0, Date.now());
  const nuevoValidoHasta = new Date(base + dias * 24 * 60 * 60 * 1000).toISOString();

  const { rows } = await query(
    `UPDATE suscripciones SET estado = 'active', valido_hasta = $2
     WHERE id = $1 RETURNING ${SAFE_COLUMNS}`,
    [id, nuevoValidoHasta],
  );
  if (!rows[0]) throw new Error(`Suscripción no encontrada: ${id}`);
  return rows[0];
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
  financeSeries,
  cancelById,
  extendById,
};
