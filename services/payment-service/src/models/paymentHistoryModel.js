/**
 * @file services/payment-service/src/models/paymentHistoryModel.js
 * @description Capa de datos del ledger inmutable payment_service_db.historial_pagos.
 * Cada pago presencial (efectivo o terminal física) genera un asiento aquí.
 * Ver migración docs/database/schemas/migrations/004_add_historial_pagos_and_courtesy.sql
 */

'use strict';

const { getSupabaseClient }   = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:paymentHistoryModel');

/**
 * Genera un folio legible de recibo: EF-YYYYMMDD-XXXX (efectivo) o TP- (terminal).
 * @param {string} metodoPago
 * @returns {string}
 */
function generateReceiptFolio(metodoPago) {
  const prefix = metodoPago === 'card_terminal' ? 'TP' : 'EF';
  const d = new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  const rand = Math.floor(1000 + Math.random() * 9000);
  return `${prefix}-${ymd}-${rand}`;
}

/**
 * Registra un asiento en el ledger de pagos presenciales.
 *
 * @param {object} params
 * @param {string}  params.usuarioId
 * @param {string}  params.suscripcionId
 * @param {number}  params.monto
 * @param {string}  [params.metodoPago='cash']    - 'cash' | 'card_terminal' | 'transfer'
 * @param {string}  [params.planNombre]
 * @param {number}  [params.planDuracionDias]
 * @param {string}  [params.periodoDesde]         - ISO8601
 * @param {string}  [params.periodoHasta]         - ISO8601
 * @param {string}  [params.paseCortesiaCodigo]
 * @param {string}  params.receptionistId
 * @param {string}  [params.notas]
 * @returns {Promise<object>} Asiento creado (incluye numero_recibo generado)
 */
async function recordCashPayment({
  usuarioId,
  suscripcionId,
  monto,
  metodoPago = 'cash',
  planNombre = null,
  planDuracionDias = null,
  periodoDesde = null,
  periodoHasta = null,
  paseCortesiaCodigo = null,
  receptionistId,
  notas = null,
}) {
  const db          = getSupabaseClient();
  const numeroRecibo = generateReceiptFolio(metodoPago);

  const { data, error } = await db
    .from('historial_pagos')
    .insert({
      usuario_id:            usuarioId,
      suscripcion_id:        suscripcionId,
      monto,
      moneda:                'MXN',
      metodo_pago:           metodoPago,
      estado_pago:           'completed',
      plan_nombre:           planNombre,
      plan_duracion_dias:    planDuracionDias,
      periodo_desde:         periodoDesde,
      periodo_hasta:         periodoHasta,
      numero_recibo:         numeroRecibo,
      pase_cortesia_codigo:  paseCortesiaCodigo,
      receptionist_id:       receptionistId,
      notas,
    })
    .select('*')
    .single();

  if (error) {
    logger.error('Error registrando asiento en historial_pagos', {
      usuarioId, receptionistId, error: error.message,
    });
    throw error;
  }

  logger.info('Asiento de pago presencial registrado', {
    id: data.id, usuarioId, monto, numeroRecibo, metodoPago,
  });
  return data;
}

/**
 * Registra un asiento de pago ONLINE (Stripe) en el ledger. Lo invoca el webhook
 * invoice.paid. Es IDEMPOTENTE: el índice único uq_hp_stripe_event impide que un
 * mismo evento se asiente dos veces (una re-entrega de Stripe → 23505 → no-op).
 *
 * @param {object} params
 * @param {string}  params.usuarioId
 * @param {string}  [params.suscripcionId]
 * @param {number}  params.monto                 - Monto cobrado (>0), en unidades (no centavos)
 * @param {string}  [params.moneda='MXN']
 * @param {string}  [params.planNombre]
 * @param {number}  [params.planDuracionDias]
 * @param {string}  [params.periodoDesde]        - ISO8601
 * @param {string}  [params.periodoHasta]        - ISO8601
 * @param {string}  params.stripeEventId         - evt_… (trazabilidad + idempotencia)
 * @param {string}  [params.numeroRecibo]        - nº de factura Stripe
 * @returns {Promise<object|null>} Asiento creado, o null si ya existía.
 */
async function recordOnlinePayment({
  usuarioId,
  suscripcionId = null,
  monto,
  moneda = 'MXN',
  planNombre = null,
  planDuracionDias = null,
  periodoDesde = null,
  periodoHasta = null,
  stripeEventId,
  numeroRecibo = null,
}) {
  const db = getSupabaseClient();

  const { data, error } = await db
    .from('historial_pagos')
    .insert({
      usuario_id:         usuarioId,
      suscripcion_id:     suscripcionId,
      monto,
      moneda,
      metodo_pago:        'stripe',
      estado_pago:        'completed',
      plan_nombre:        planNombre,
      plan_duracion_dias: planDuracionDias,
      periodo_desde:      periodoDesde,
      periodo_hasta:      periodoHasta,
      numero_recibo:      numeroRecibo,
      receptionist_id:    null,
      stripe_event_id:    stripeEventId,
    })
    .select('id, numero_recibo')
    .single();

  if (error) {
    if (error.code === '23505') {
      // Evento ya asentado (re-entrega de Stripe) → idempotente, no es error.
      logger.info('Pago online ya asentado, se omite (evento duplicado)', { stripeEventId });
      return null;
    }
    logger.error('Error asentando pago online en historial_pagos', {
      usuarioId, stripeEventId, error: error.message,
    });
    throw error;
  }

  logger.info('Asiento de pago online (Stripe) registrado', {
    id: data.id, usuarioId, monto, stripeEventId,
  });
  return data;
}

module.exports = { recordCashPayment, recordOnlinePayment, generateReceiptFolio };
