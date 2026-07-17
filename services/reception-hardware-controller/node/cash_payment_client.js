/**
 * @file services/reception-hardware-controller/node/cash_payment_client.js
 * @description Cliente local de MOSTRADOR para registrar pagos presenciales (efectivo /
 * terminal física) contra payment-service en Railway y disparar la impresión del ticket.
 *
 * RESILIENCIA ANTE CAÍDA DE RED LOCAL (Tarea 3.4 — manejo de excepciones):
 *   Si el internet del gimnasio o Railway están caídos al momento de cobrar, el pago
 *   NO se pierde ni bloquea la caja: se encola en 'pending_cash_payments.jsonl' con una
 *   clave de idempotencia y se reintenta automáticamente (backoff) cuando vuelve la línea.
 *   El recepcionista recibe confirmación "encolado" y puede entregar un ticket provisional.
 *
 *   Distinción de errores:
 *     • Error de RED / HTTP 5xx  → se ENCOLA y reintenta (fallo transitorio del servidor).
 *     • Error HTTP 4xx (validación / API Key)→ NO se encola (reintentar no ayuda); se informa al staff.
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const crypto = require('crypto');
const axios  = require('axios');

const CONFIG = {
  paymentServiceUrl: (process.env.PAYMENT_SERVICE_URL
    || 'https://payment-service.gympro.railway.app').replace(/\/+$/, ''),
  cashApiKey:  process.env.CASH_PAYMENT_API_KEY || 'gympro_cash_rec01_changeme',
  cashEndpoint: '/api/v1/payments/cash-payment',
  requestTimeoutMs: parseInt(process.env.CASH_REQUEST_TIMEOUT_MS || '6000', 10),
  pendingPath: path.join(__dirname, 'logs', 'pending_cash_payments.jsonl'),
  maxRetries:  parseInt(process.env.CASH_MAX_RETRIES || '20', 10),
};

if (!fs.existsSync(path.dirname(CONFIG.pendingPath))) {
  fs.mkdirSync(path.dirname(CONFIG.pendingPath), { recursive: true });
}

let isFlushing = false;

/**
 * Envía el cobro a payment-service.
 * @param {object} sale - { usuario_id, monto, plan_duracion_dias, plan_nombre?, metodo_pago?, notas? }
 * @returns {Promise<{ ok: boolean, status: number, data?: object, error?: string, retriable: boolean }>}
 */
async function postCashPayment(sale) {
  try {
    const response = await axios.post(
      `${CONFIG.paymentServiceUrl}${CONFIG.cashEndpoint}`,
      {
        usuario_id:         sale.usuario_id,
        monto:              sale.monto,
        plan_duracion_dias: sale.plan_duracion_dias ?? 30,
        plan_nombre:        sale.plan_nombre,
        metodo_pago:        sale.metodo_pago ?? 'cash',
        notas:              sale.notas ?? null,
      },
      {
        headers: {
          'x-api-key':          CONFIG.cashApiKey,
          'Content-Type':       'application/json',
          'Idempotency-Key':    sale._idempotency_key,
        },
        timeout: CONFIG.requestTimeoutMs,
      },
    );
    return { ok: true, status: response.status, data: response.data?.data || {} , retriable: false };
  } catch (err) {
    const status = err.response?.status;
    if (status && status >= 400 && status < 500) {
      // Error del cliente (validación, API Key): NO reintentar.
      return {
        ok: false, status,
        error: err.response?.data?.error || `Rechazado (${status})`,
        retriable: false,
      };
    }
    // Sin respuesta (red caída), timeout o 5xx: reintento diferido.
    return {
      ok: false,
      status: status || 0,
      error: err.response?.data?.error || err.message,
      retriable: true,
    };
  }
}

function enqueuePending(sale, reason) {
  const record = { ...sale, queued_at: new Date().toISOString(), last_error: reason, attempts: (sale.attempts || 0) };
  fs.appendFileSync(CONFIG.pendingPath, JSON.stringify(record) + '\n', 'utf8');
  console.log(`📂 [Caja Offline] Pago de '${sale.usuario_id}' encolado localmente (${reason}).`);
}

/**
 * Punto de entrada desde el panel de mostrador. Cobra y, si hay éxito, imprime el ticket.
 *
 * @param {object} sale
 * @param {(ticket:object)=>Promise<object>} printTicket - Dispatcher de impresora local (printDailyTicket)
 * @returns {Promise<object>} Resultado apto para responder al panel (nunca lanza).
 */
async function registerCashPayment(sale, printTicket) {
  // Clave de idempotencia estable para evitar cobros dobles en reintentos.
  sale._idempotency_key = sale._idempotency_key
    || crypto.createHash('sha256')
        .update(`${sale.usuario_id}|${sale.monto}|${sale.plan_duracion_dias}|${Date.now()}`)
        .digest('hex').slice(0, 32);

  const result = await postCashPayment(sale);

  if (result.ok) {
    const ticket = result.data?.ticket_impresion;
    let printResult = { print_status: 'skipped', mensaje: 'Sin payload de ticket.' };
    if (ticket && typeof printTicket === 'function') {
      printResult = await printTicket(ticket);
    }
    return {
      success: true,
      estado_pago: 'confirmado',
      mensaje: `Pago confirmado. Recibo ${result.data?.numero_recibo || 's/n'}. Acceso sincronizado.`,
      pago: result.data,
      impresion: printResult,
    };
  }

  if (result.retriable) {
    enqueuePending(sale, result.error);
    return {
      success: true,               // No bloqueamos la caja: 200 con estado "encolado".
      estado_pago: 'encolado_offline',
      mensaje: 'Sin conexión con el servidor central. El pago quedó guardado y se sincronizará automáticamente al volver la red.',
      idempotency_key: sale._idempotency_key,
    };
  }

  // Error no reintentable (4xx): informar al staff para que corrija.
  return {
    success: false,
    estado_pago: 'rechazado',
    mensaje: result.error,
    status: result.status,
  };
}

/**
 * Reintenta los pagos encolados por caídas de red. Se invoca en el bucle Auto-Healer.
 * @param {(ticket:object)=>Promise<object>} printTicket
 */
async function flushPendingCashPayments(printTicket) {
  if (isFlushing) return;
  if (!fs.existsSync(CONFIG.pendingPath)) return;

  const content = fs.readFileSync(CONFIG.pendingPath, 'utf8').trim();
  if (!content) return;

  isFlushing = true;
  const lines = content.split('\n').filter((l) => l.trim());
  console.log(`🚀 [Caja Offline] Reintentando ${lines.length} pago(s) pendiente(s)...`);

  const remaining = [];
  for (const line of lines) {
    let sale;
    try { sale = JSON.parse(line); } catch { continue; }
    sale.attempts = (sale.attempts || 0) + 1;

    const result = await postCashPayment(sale);
    if (result.ok) {
      const ticket = result.data?.ticket_impresion;
      if (ticket && typeof printTicket === 'function') {
        await printTicket({ ...ticket, notas: `${ticket.notas || ''} [SINCRONIZADO]` });
      }
      console.log(`✅ [Caja Offline] Pago de '${sale.usuario_id}' sincronizado (intento ${sale.attempts}).`);
    } else if (result.retriable && sale.attempts < CONFIG.maxRetries) {
      remaining.push(JSON.stringify(sale));
    } else {
      // 4xx o agotó reintentos: sacar de la cola y dejar traza para revisión manual.
      console.error(`🛑 [Caja Offline] Pago de '${sale.usuario_id}' descartado tras ${sale.attempts} intentos: ${result.error}`);
    }
  }

  fs.writeFileSync(CONFIG.pendingPath, remaining.join('\n') + (remaining.length ? '\n' : ''), 'utf8');
  isFlushing = false;
  if (!remaining.length) {
    console.log('✅ [Caja Offline] Cola de pagos vacía: todo sincronizado.');
  }
}

module.exports = { registerCashPayment, flushPendingCashPayments, CONFIG };
