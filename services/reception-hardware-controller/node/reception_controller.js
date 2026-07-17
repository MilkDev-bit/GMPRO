/**
 * @file services/reception-hardware-controller/node/reception_controller.js
 * @description Script de Control en el Mostrador en Node.js (Lector QR, Relevador ZKTeco e Impresora 80mm).
 *
 * CUMPLE CON TAREA 5.1 & REFACTOR DE RESILIENCIA EN HARDWARE:
 *   1. RECONEXIÓN AUTOMÁTICA DE PUERTOS (Auto-Healing): Supervisa y reintenta conectar cada 3s
 *      si el cable USB/Serie del lector QR, relevador o impresora se suelta o pierde energía.
 *   2. MANEJO DE COLA DE IMPRESIÓN SORDA: Si la impresora se queda sin papel o apagada, las órdenes
 *      no bloquean la base de datos central de Supabase ni devuelven 500; se guardan en 'failed_tickets.jsonl'
 *      y se reintentan automáticamente al restablecerse la impresora.
 */

'use strict';

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const http = require('http');
const axios = require('axios');
const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');
const escpos = require('escpos');
escpos.USB = require('escpos-usb');
const cashPaymentClient = require('./cash_payment_client');

// ── CONFIGURACIÓN DEL SISTEMA ────────────────────────────────────────────────
const CONFIG = {
  railwayUrl: process.env.RAILWAY_ACCESS_SERVICE_URL || 'https://access-service.gympro.railway.app/api/v1/access',
  turnstileApiKey: process.env.TURNSTILE_API_KEY || 'turnstile_secret_key_prod_2026',
  turnstileId: process.env.TURNSTILE_ID || 'recepcion_torniquete_1',

  qrPortPath: process.env.QR_SERIAL_PORT || (process.platform === 'win32' ? 'COM3' : '/dev/ttyACM0'),
  qrBaudRate: parseInt(process.env.QR_SERIAL_BAUDRATE || '9600', 10),

  relayPortPath: process.env.RELAY_SERIAL_PORT || (process.platform === 'win32' ? 'COM4' : '/dev/ttyUSB1'),
  relayBaudRate: parseInt(process.env.RELAY_SERIAL_BAUDRATE || '9600', 10),
  pulseDurationMs: parseInt(process.env.PULSE_DURATION_MS || '1000', 10),

  printerVid: parseInt(process.env.PRINTER_USB_VID || '0x04b8', 16),
  printerPid: parseInt(process.env.PRINTER_USB_PID || '0x0e28', 16),

  failedTicketsPath: path.join(__dirname, 'logs', 'failed_tickets.jsonl'),
  autoHealIntervalMs: 3000,
};

// Asegurar directorio para log sordo
if (!fs.existsSync(path.dirname(CONFIG.failedTicketsPath))) {
  fs.mkdirSync(path.dirname(CONFIG.failedTicketsPath), { recursive: true });
}

// Comandos Hex para relevadores LCUS-1 / CH340 en puerto serial
const RELAY_CMD_OPEN  = Buffer.from('A00101A2', 'hex'); // Cierra circuito (Libera torniquete)
const RELAY_CMD_CLOSE = Buffer.from('A00100A1', 'hex'); // Abre circuito (Traba torniquete)

let relayPort = null;
let printerDevice = null;
let printerInstance = null;
let qrPort = null;
let isRelayBusy = false;
let isPrinterFlushRunning = false;
let relayWatchdog = null;

// Libera de forma segura un puerto serie: quita listeners y cierra el fd para
// evitar FUGAS de descriptores/listeners a lo largo de ciclos de reconexión.
function safeReleaseSerialPort(port) {
  if (!port) return;
  try { port.removeAllListeners(); } catch (_) {}
  try { if (port.isOpen) port.close(() => {}); } catch (_) {}
}

// Garantiza que isRelayBusy NUNCA quede atascado en true (que bloquearía el
// torniquete de forma permanente). Se llama desde finally y desde el watchdog.
function releaseRelayBusy() {
  isRelayBusy = false;
  if (relayWatchdog) { clearTimeout(relayWatchdog); relayWatchdog = null; }
}

// ── 1. RELEVADOR USB PARA TORNIQUETE ZKTECO TS1000 PLUS (CON AUTO-HEALING) ───
function initRelay() {
  if (relayPort && relayPort.isOpen) return;

  try {
    relayPort = new SerialPort({
      path: CONFIG.relayPortPath,
      baudRate: CONFIG.relayBaudRate,
      autoOpen: true,
      lock: true,
    });

    relayPort.on('open', () => {
      console.log(`⚡ [Relevador Node.js Auto-Healing] Conectado en ${CONFIG.relayPortPath}`);
      relayPort.write(RELAY_CMD_CLOSE); // Asegurar bloqueo al iniciar o reconectar
    });

    relayPort.on('close', () => {
      console.warn(`⚠️ [Relevador Node.js] Puerto ${CONFIG.relayPortPath} cerrado. El Auto-Healer actuará en 3s.`);
      const p = relayPort; relayPort = null;
      try { p && p.removeAllListeners(); } catch (_) {}
      releaseRelayBusy();
    });

    relayPort.on('error', (err) => {
      console.debug(`⏳ [Relevador Node.js] Error en puerto o desconectado: ${err.message}`);
      safeReleaseSerialPort(relayPort);
      relayPort = null;
      releaseRelayBusy();
    });
  } catch (err) {
    relayPort = null;
  }
}

async function triggerTurnstileUnlock() {
  if (isRelayBusy) {
    console.warn('⏳ [Relevador Node.js] Relevador ocupado. Ignorando pulso simultáneo.');
    return;
  }
  isRelayBusy = true;
  // Watchdog de seguridad: si cualquier ruta falla en liberar el flag, este timer
  // lo fuerza y el torniquete vuelve a operar (evita bloqueo permanente).
  relayWatchdog = setTimeout(() => {
    console.warn('⏱️ [Relevador Node.js] Watchdog liberó isRelayBusy tras timeout de seguridad.');
    isRelayBusy = false;
    relayWatchdog = null;
  }, CONFIG.pulseDurationMs + 2000);

  console.log(`🔓 [Relevador Node.js] ACTIVANDO APERTURA DE TORNIQUETE por ${CONFIG.pulseDurationMs}ms (ZKTeco TS1000 Plus)...`);

  if (relayPort && relayPort.isOpen) {
    try {
      relayPort.write(RELAY_CMD_OPEN);
    } catch (err) {
      console.error(`❌ [Relevador Node.js] Error de I/O escribiendo pulso: ${err.message}`);
      safeReleaseSerialPort(relayPort);
      relayPort = null;
      releaseRelayBusy();
      return;
    }
    setTimeout(() => {
      try {
        if (relayPort && relayPort.isOpen) {
          relayPort.write(RELAY_CMD_CLOSE);
          console.log('🔒 [Relevador Node.js] Circuito reabierto. Torniquete asegurado.');
        }
      } catch (err) {
        console.error(`❌ [Relevador Node.js] Error cerrando pulso: ${err.message}`);
        safeReleaseSerialPort(relayPort);
        relayPort = null;
      } finally {
        // finally garantiza el reset de isRelayBusy pase lo que pase.
        releaseRelayBusy();
      }
    }, CONFIG.pulseDurationMs);
  } else {
    console.log(`💡 [Simulación] Circuito CERRADO -> Esperando ${CONFIG.pulseDurationMs}ms...`);
    setTimeout(() => {
      console.log('💡 [Simulación] Circuito ABIERTO.');
      releaseRelayBusy();
    }, CONFIG.pulseDurationMs);
  }
}

// ── 2. IMPRESORA TÉRMICA USB 80MM (CON COLA SORDA Y AUTO-HEALING) ────────────
function initPrinter() {
  if (printerDevice && printerInstance) return;

  try {
    printerDevice = new escpos.USB(CONFIG.printerVid, CONFIG.printerPid);
    printerInstance = new escpos.Printer(printerDevice);
    console.log(`🖨️ [Impresora Node.js Auto-Healing] Conectada por USB (VID=0x${CONFIG.printerVid.toString(16)})`);
    flushOfflineTicketQueue();
  } catch (err) {
    printerDevice = null;
    printerInstance = null;
  }
}

function enqueueSilentTicket(payload, reason) {
  try {
    const record = {
      ...payload,
      failed_at: new Date().toISOString(),
      error_reason: reason,
    };
    fs.appendFileSync(CONFIG.failedTicketsPath, JSON.stringify(record) + '\n', 'utf8');
    console.log(`📂 [Cola Sorda Node.js] Ticket '${payload.codigo_ticket}' guardado localmente en log de fallos.`);
  } catch (err) {
    console.error(`❌ [Cola Sorda Node.js] Error escribiendo en log sordo: ${err.message}`);
  }
}

async function flushOfflineTicketQueue() {
  if (isPrinterFlushRunning || !printerDevice || !printerInstance) return;
  if (!fs.existsSync(CONFIG.failedTicketsPath)) return;

  const content = fs.readFileSync(CONFIG.failedTicketsPath, 'utf8').trim();
  if (!content) return;

  isPrinterFlushRunning = true;
  const lines = content.split('\n').filter(l => l.trim());
  console.log(`🚀 [Cola Sorda Node.js] Purgando ${lines.length} ticket(s) pendientes tras reconexión...`);

  const remaining = [];
  for (const line of lines) {
    try {
      const item = JSON.parse(line);
      const res = await printDailyTicketInternal({
        codigo_ticket: item.codigo_ticket,
        qr_string: item.qr_string || item.codigo_ticket,
        vigencia_horas: item.vigencia_horas || 24,
        user_name: `${item.user_name || 'Visita GymPro'} [RETRY]`,
        notas: item.notas,
      });
      if (res.print_status !== 'printed') {
        remaining.push(line);
      }
    } catch (e) {
      remaining.push(line);
    }
  }

  fs.writeFileSync(CONFIG.failedTicketsPath, remaining.join('\n') + (remaining.length ? '\n' : ''), 'utf8');
  isPrinterFlushRunning = false;
  if (!remaining.length) {
    console.log('✅ [Cola Sorda Node.js] Todos los tickets pendientes se imprimieron y el log quedó limpio.');
  }
}

async function printDailyTicket(payload) {
  return printDailyTicketInternal(payload);
}

function printDailyTicketInternal({ codigo_ticket = 'GP-000', qr_string = '', vigencia_horas = 24, user_name = 'Visita GymPro', notas = null }) {
  console.log(`🖨️ [Impresora Node.js] Procesando ticket de 80mm para '${codigo_ticket}' (${user_name})...`);

  if (!printerDevice || !printerInstance) {
    // Si no está conectada, encolar en silencio y responder éxito con advertencia para no bloquear servidor
    enqueueSilentTicket({ codigo_ticket, qr_string, vigencia_horas, user_name, notas }, 'IMPRESORA_OFFLINE');
    return Promise.resolve({
      success: true,
      print_status: 'queued_offline',
      mensaje: 'Impresora offline/sin papel. Ticket encolado localmente en log de auditoría sorda.',
    });
  }

  return new Promise((resolve) => {
    printerDevice.open((err) => {
      if (err) {
        console.error(`❌ [Impresora Node.js] Error abriendo canal USB (${err.message}). Encolando en log sordo...`);
        printerDevice = null;
        printerInstance = null;
        enqueueSilentTicket({ codigo_ticket, qr_string, vigencia_horas, user_name, notas }, err.message);
        return resolve({
          success: true,
          print_status: 'queued_offline',
          mensaje: 'Impresora temporalmente inaccesible. Ticket guardado en cola sorda sin bloquear base de datos.',
        });
      }

      try {
        printerInstance
          .font('a')
          .align('ct')
          .style('bu')
          .size(2, 2)
          .text('GYMPRO AI FITNESS')
          .style('NORMAL')
          .size(1, 1)
          .text('SISTEMA BIOMETRICO Y ACCESO')
          .text('--------------------------------')
          .text('PASE DE VISITA DIARIA\n')
          .align('lt')
          .text(`Socio/Visita : ${user_name}`)
          .text(`Emitido      : ${new Date().toLocaleString()}`)
          .text(`Vigencia     : ${vigencia_horas} Horas`)
          .text(`Codigo Pase  : ${codigo_ticket}`);

        if (notas) printerInstance.text(`Notas        : ${notas}`);
        printerInstance.text('--------------------------------\n').align('ct');

        printerInstance.qrimage(qr_string || codigo_ticket, { type: 'png', size: 3 }, (qrErr) => {
          if (qrErr) console.warn('⚠️ Error renderizando QR en impresora, usando texto crudo.');
          printerInstance
            .text(`\n[${codigo_ticket}]\n`)
            .text('Presente este codigo en la lectora\ndel torniquete para ingresar.\n')
            .text('Valido para 1 solo ingreso.\n\n\n')
            .cut()
            .close();
          console.log('✅ [Impresora Node.js] Ticket impreso y cortado.');
          resolve({ success: true, print_status: 'printed', mensaje: 'Ticket impreso en papel de 80mm.' });
        });
      } catch (printErr) {
        console.error(`❌ [Impresora Node.js] Excepción durante impresión (${printErr.message}). Encolando sordo...`);
        try { printerDevice.close(); } catch (e) {}
        printerDevice = null;
        printerInstance = null;
        enqueueSilentTicket({ codigo_ticket, qr_string, vigencia_horas, user_name, notas }, printErr.message);
        resolve({
          success: true,
          print_status: 'queued_offline',
          mensaje: 'Error durante comandos ESC/POS. Ticket encolado localmente en auditoría sorda.',
        });
      }
    });
  });
}

// ── 3. LECTOR QR OMNIDIRECCIONAL (EXCLUSIVO + AUTO-HEALING) ──────────────────
function initQrScanner() {
  if (qrPort && qrPort.isOpen) return;

  try {
    qrPort = new SerialPort({
      path: CONFIG.qrPortPath,
      baudRate: CONFIG.qrBaudRate,
      lock: true, // EXCLUSIVO: Intercepta lecturas para no filtrarse a Excel/Navegador en la PC
    });

    const parser = qrPort.pipe(new ReadlineParser({ delimiter: '\n' }));

    qrPort.on('open', () => {
      console.log(`📟 [Lector QR Node.js Auto-Healing] Conectado y escuchando en ${CONFIG.qrPortPath} @ ${CONFIG.qrBaudRate} bps`);
    });

    parser.on('data', async (line) => {
      const code = line.toString().trim();
      if (!code) return;
      console.log(`\n⚡ [Lector QR Node.js] Código interceptado: '${code}'`);
      await validateAndProcessCode(code);
    });

    qrPort.on('close', () => {
      console.warn(`⚠️ [Lector QR Node.js] Puerto ${CONFIG.qrPortPath} cerrado o desconectado. Auto-Healer actuará en 3s.`);
      const p = qrPort; qrPort = null;
      try { p && p.removeAllListeners(); } catch (_) {}
    });

    qrPort.on('error', (err) => {
      console.debug(`⏳ [Lector QR Node.js] Error de puerto (${err.message}). Esperando reconexión...`);
      safeReleaseSerialPort(qrPort);
      qrPort = null;
    });
  } catch (err) {
    qrPort = null;
  }
}

async function validateAndProcessCode(code) {
  const isTicket = code.toUpperCase().startsWith('GP-') || (code.length === 15 && code.includes('-'));
  const endpoint = `${CONFIG.railwayUrl}/${isTicket ? 'validate-ticket' : 'validate-qr'}`;
  const payload = isTicket ? { codigo_ticket: code } : { token_qr: code };

  try {
    console.log(`🌐 [Railway API] Enviando a ${endpoint}...`);
    const response = await axios.post(endpoint, payload, {
      headers: {
        'X-Turnstile-API-Key': CONFIG.turnstileApiKey,
        'X-Turnstile-Id': CONFIG.turnstileId,
      },
      timeout: 3500,
    });

    const respData = response.data?.data || {};
    const accesoConcedido = respData.acceso_concedido || respData.apertura_torniquete;

    if (response.status === 200 && accesoConcedido) {
      console.log(`🎉 [ACCESO AUTORIZADO] -> ${respData.mensaje || 'Paso concedido'}`);
      await triggerTurnstileUnlock();
    } else {
      console.warn(`🛑 [ACCESO RECHAZADO] -> ${respData.mensaje || 'Denegado'}`);
    }
  } catch (err) {
    const status = err.response?.status || 'RED_ERROR';
    const msg = err.response?.data?.error || err.message;
    console.error(`❌ [Railway API Error (${status})] ${msg}`);
  }
}

// ── 4. SUPERVISOR EN SEGUNDO PLANO (AUTO-HEALING CADA 3 SEGUNDOS) ────────────
function startAutoHealerLoop() {
  setInterval(() => {
    // 1. Revisar y reconectar Relevador si se soltó el cable USB
    if (!relayPort || !relayPort.isOpen) {
      initRelay();
    }
    // 2. Revisar y reconectar Lector QR si se desconectó o reinició
    if (!qrPort || !qrPort.isOpen) {
      initQrScanner();
    }
    // 3. Revisar Impresora y purgar cola de tickets fallidos
    if (!printerDevice || !printerInstance) {
      initPrinter();
    } else {
      flushOfflineTicketQueue();
    }
    // 4. Reintentar pagos en efectivo que quedaron encolados por caídas de red.
    cashPaymentClient.flushPendingCashPayments(printDailyTicket);
  }, CONFIG.autoHealIntervalMs);
  console.log(`🛡️ [Auto-Healing] Bucle supervisor activo: verificando puertos USB/COM cada ${CONFIG.autoHealIntervalMs / 1000} segundos.`);
}

// ── 5. SERVIDOR HTTP LOCAL PARA IMPRESIÓN DE TICKETS DESDE MOSTRADOR ─────────
function startLocalHttpServer(port = 18999) {
  const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && (req.url === '/print-ticket' || req.url === '/api/print-ticket')) {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', async () => {
        try {
          const payload = JSON.parse(body || '{}');
          const result = await printDailyTicket(payload);
          // NUNCA devolvemos 500 si la impresora se quedó sin papel: se encola en silencio devolviendo 200/202
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result));
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: err.message }));
        }
      });
    } else if (req.method === 'POST' && (req.url === '/register-cash-payment' || req.url === '/api/register-cash-payment')) {
      // ── Cobro presencial desde el panel de mostrador ────────────────────────
      // Dispara el pago a payment-service (Railway) y, si hay éxito, imprime el
      // ticket con el pase de cortesía. Ante caída de red, encola y responde 200.
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', async () => {
        try {
          const sale = JSON.parse(body || '{}');
          if (!sale.usuario_id || !(Number(sale.monto) > 0)) {
            res.writeHead(422, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: false, error: 'usuario_id y monto (> 0) son requeridos.' }));
            return;
          }
          const result = await cashPaymentClient.registerCashPayment(sale, printDailyTicket);
          // 200 siempre que el pago quede confirmado o encolado; 402 solo si fue rechazado por el servidor.
          res.writeHead(result.success ? 200 : 402, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result));
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: false, error: err.message }));
        }
      });
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  server.listen(port, '127.0.0.1', () => {
    console.log(`🌐 [Servidor Node.js] Escuchando órdenes de impresión en http://127.0.0.1:${port}/print-ticket`);
  });
}

// ── BOOTSTRAP DEL SISTEMA ────────────────────────────────────────────────────
console.log('================================================================================');
console.log('   🚀 GYMPRO AI — CONTROLADOR LOCAL DE RECEPCIÓN Y HARDWARE (Node.js 20+)');
console.log('================================================================================');
initRelay();
initPrinter();
initQrScanner();
startAutoHealerLoop();
startLocalHttpServer(18999);
