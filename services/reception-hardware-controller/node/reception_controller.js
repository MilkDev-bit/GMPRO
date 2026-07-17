/**
 * @file services/reception-hardware-controller/node/reception_controller.js
 * @description Script de Control en el Mostrador en Node.js (Lector QR, Relevador ZKTeco e Impresora 80mm).
 *
 * CUMPLE CON TAREA 5.1:
 *   1. Escucha en segundo plano el puerto serie/COM del lector QR omnidireccional (lock=true).
 *   2. Envía peticiones HTTP POST a access-service en Railway. Si acceso_concedido === true, activa un pulso
 *      de 1 segundo al puerto del relevador USB para destrabar el torniquete ZKTeco TS1000 Plus.
 *   3. Imprime tickets térmicos de 80mm usando comandos ESC/POS para pases de visita diaria con QR.
 */

'use strict';

require('dotenv').config();
const http = require('http');
const axios = require('axios');
const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');
const escpos = require('escpos');
escpos.USB = require('escpos-usb');

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
};

// Comandos Hex para relevadores LCUS-1 / CH340 en puerto serial
const RELAY_CMD_OPEN  = Buffer.from('A00101A2', 'hex'); // Cierra circuito (Libera torniquete)
const RELAY_CMD_CLOSE = Buffer.from('A00100A1', 'hex'); // Abre circuito (Traba torniquete)

let relayPort = null;
let printerDevice = null;
let printerInstance = null;
let isRelayBusy = false;

// ── 1. INICIALIZAR RELEVADOR USB PARA TORNIQUETE ZKTECO TS1000 PLUS ──────────
function initRelay() {
  try {
    relayPort = new SerialPort({
      path: CONFIG.relayPortPath,
      baudRate: CONFIG.relayBaudRate,
      autoOpen: true,
      lock: true,
    });

    relayPort.on('open', () => {
      console.log(`⚡ [Relevador Node.js] Conectado exitosamente en ${CONFIG.relayPortPath}`);
      relayPort.write(RELAY_CMD_CLOSE); // Asegurar bloqueo inicial
    });

    relayPort.on('error', (err) => {
      console.error(`❌ [Relevador Node.js] Error en puerto serie: ${err.message}`);
      relayPort = null;
    });
  } catch (err) {
    console.warn(`⚠️ [Relevador Node.js] No se pudo abrir puerto ${CONFIG.relayPortPath}. Modo simulación activado.`);
    relayPort = null;
  }
}

/**
 * Dispara un pulso al relevador para abrir el torniquete por 1 segundo exacto.
 */
async function triggerTurnstileUnlock() {
  if (isRelayBusy) {
    console.warn('⏳ [Relevador Node.js] Relevador ocupado. Ignorando pulso simultáneo.');
    return;
  }
  isRelayBusy = true;
  console.log(`🔓 [Relevador Node.js] ACTIVANDO APERTURA DE TORNIQUETE por ${CONFIG.pulseDurationMs}ms (ZKTeco TS1000 Plus)...`);

  if (relayPort && relayPort.isOpen) {
    relayPort.write(RELAY_CMD_OPEN);
    setTimeout(() => {
      relayPort.write(RELAY_CMD_CLOSE);
      console.log('🔒 [Relevador Node.js] Circuito reabierto. Torniquete asegurado.');
      isRelayBusy = false;
    }, CONFIG.pulseDurationMs);
  } else {
    // Simulación en desarrollo
    console.log(`💡 [Simulación] Circuito CERRADO -> Esperando ${CONFIG.pulseDurationMs}ms...`);
    setTimeout(() => {
      console.log('💡 [Simulación] Circuito ABIERTO.');
      isRelayBusy = false;
    }, CONFIG.pulseDurationMs);
  }
}

// ── 2. INICIALIZAR IMPRESORA TÉRMICA USB DE 80MM (ESC/POS) ───────────────────
function initPrinter() {
  try {
    printerDevice = new escpos.USB(CONFIG.printerVid, CONFIG.printerPid);
    printerInstance = new escpos.Printer(printerDevice);
    console.log(`🖨️ [Impresora Node.js] Conectada por USB (VID=0x${CONFIG.printerVid.toString(16)})`);
  } catch (err) {
    console.warn('⚠️ [Impresora Node.js] Impresora USB no encontrada o sin drivers. Modo simulación activado.');
    printerDevice = null;
    printerInstance = null;
  }
}

/**
 * Imprime un ticket de pase diario con código QR óptico usando comandos ESC/POS.
 */
function printDailyTicket({ codigo_ticket, qr_string, vigencia_horas = 24, user_name = 'Visita GymPro', notas = null }) {
  console.log(`🖨️ [Impresora Node.js] Generando ticket de 80mm para '${codigo_ticket}' (${user_name})...`);

  if (!printerDevice || !printerInstance) {
    console.log(`
====================================
        GYMPRO AI FITNESS
     PASE DE VISITA DIARIA (80mm)
====================================
 Socio/Visita : ${user_name}
 Emitido      : ${new Date().toLocaleString()}
 Vigencia     : ${vigencia_horas} Horas
 Código       : ${codigo_ticket}
------------------------------------
     [ CÓDIGO QR ÓPTICO ESC/POS ]
       DATA -> ${qr_string}
------------------------------------
====================================
`);
    return Promise.resolve(true);
  }

  return new Promise((resolve, reject) => {
    printerDevice.open((err) => {
      if (err) {
        console.error(`❌ [Impresora Node.js] Error abriendo canal USB: ${err}`);
        return reject(err);
      }

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
        .text(`Codigo Pase  : ${codigo_ticket}`)
        .text('--------------------------------\n')
        .align('ct')
        .qrimage(qr_string, { type: 'png', size: 3 }, (qrErr) => {
          if (qrErr) console.warn('⚠️ Error renderizando QR en impresora, imprimiendo texto como fallback.');
          printerInstance
            .text(`\n[${codigo_ticket}]\n`)
            .text('Presente este codigo en la lectora\ndel torniquete para ingresar.\n')
            .text('Valido para 1 solo ingreso.\n\n\n')
            .cut()
            .close();
          console.log('✅ [Impresora Node.js] Ticket impreso y cortado.');
          resolve(true);
        });
    });
  });
}

// ── 3. LECTOR QR OMNIDIRECCIONAL EN MODO EXCLUSIVO (LOCK) ───────────────────
function initQrScanner() {
  try {
    const qrPort = new SerialPort({
      path: CONFIG.qrPortPath,
      baudRate: CONFIG.qrBaudRate,
      lock: true, // ¡EXCLUSIVO! Intercepta lecturas en background para no filtrarse a otras apps abiertas
    });

    const parser = qrPort.pipe(new ReadlineParser({ delimiter: '\n' }));

    console.log(`📟 [Lector QR Node.js] Escuchando en modo EXCLUSIVO en ${CONFIG.qrPortPath} @ ${CONFIG.qrBaudRate} bps`);

    parser.on('data', async (line) => {
      const code = line.toString().trim();
      if (!code) return;

      console.log(`\n⚡ [Lector QR Node.js] Código interceptado: '${code}'`);
      await validateAndProcessCode(code);
    });

    qrPort.on('error', (err) => {
      console.error(`❌ [Lector QR Node.js] Error en puerto serie: ${err.message}`);
    });
  } catch (err) {
    console.warn(`⚠️ [Lector QR Node.js] No se pudo abrir ${CONFIG.qrPortPath} en modo COM. Verifique cables.`);
  }
}

/**
 * Envía el código al microservicio en Railway y procesa la respuesta.
 */
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

// ── 4. SERVIDOR HTTP LOCAL PARA IMPRESIÓN DE TICKETS DESDE MOSTRADOR ────────
function startLocalHttpServer(port = 18999) {
  const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && (req.url === '/print-ticket' || req.url === '/api/print-ticket')) {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', async () => {
        try {
          const payload = JSON.parse(body || '{}');
          await printDailyTicket(payload);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: true, mensaje: 'Ticket impreso en 80mm.' }));
        } catch (err) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
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
startLocalHttpServer(18999);
