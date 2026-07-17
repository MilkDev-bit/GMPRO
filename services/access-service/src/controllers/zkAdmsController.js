/**
 * @file services/access-service/src/controllers/zkAdmsController.js
 * @description Controladores para endpoints HTTP de sincronización ZKTeco ADMS (iClock / Push).
 * Responde directamente a las terminales biométricas SpeedFace-V5L cuando consultan al servidor
 * y expone endpoints administrativos/M2M para encolar cargas y borrados de rostros.
 */

'use strict';

const zkAdmsService           = require('../services/zkAdmsService');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:zkAdmsController');

// ── 1. ENDPOINTS DEL PROTOCOLO ICLOCK PUSH (DIRECTO DE TERMINALES SPEEDFACE) ─

/**
 * GET /iclock/getrequest?SN=<SERIAL_NUMBER>
 * La terminal biométrica sondea este endpoint cada pocos segundos preguntando por comandos pendientes.
 * Si hay comandos en cola, se retornan en texto plano separados por '\n'. Si no, se retorna 'OK'.
 */
async function handleGetRequest(req, res, next) {
  try {
    const serialNumber = req.query.SN || req.query.sn || 'UNKNOWN_SN';
    const redisClient  = req.redisClient;

    logger.debug(`[ADMS Poll] Terminal SN=${serialNumber} solicitando comandos (/getrequest)`);

    const responseText = await zkAdmsService.getPendingCommandsForDevice(serialNumber, redisClient);

    // Las terminales ZKTeco requieren cabecera Content-Type de texto plano
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.status(200).send(responseText);
  } catch (err) {
    logger.error('Error en handleGetRequest ADMS', { error: err.message });
    res.setHeader('Content-Type', 'text/plain');
    return res.status(500).send('ERROR');
  }
}

/**
 * POST /iclock/devicecmd?SN=<SERIAL_NUMBER>
 * La terminal confirma la ejecución de un comando enviando body en formato form o texto:
 * ID=<COMMAND_ID>&Return=<0|-1>&CMD=...
 */
async function handleDeviceCmd(req, res, next) {
  try {
    const serialNumber = req.query.SN || req.query.sn || 'UNKNOWN_SN';
    const redisClient  = req.redisClient;

    // Obtener parámetros de query o body parsed (form-urlencoded o raw text)
    const commandId  = req.body?.ID || req.query.ID;
    const returnCode = req.body?.Return !== undefined ? req.body.Return : req.query.Return;

    if (commandId !== undefined && returnCode !== undefined) {
      await zkAdmsService.processCommandResult(serialNumber, commandId, returnCode, redisClient);
    } else if (typeof req.body === 'string' && req.body.includes('ID=')) {
      // Parsear manual si vino en raw string
      const params = new URLSearchParams(req.body);
      const rawId  = params.get('ID');
      const rawRet = params.get('Return');
      if (rawId && rawRet !== null) {
        await zkAdmsService.processCommandResult(serialNumber, rawId, rawRet, redisClient);
      }
    }

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.status(200).send('OK');
  } catch (err) {
    logger.error('Error en handleDeviceCmd ADMS', { error: err.message });
    res.setHeader('Content-Type', 'text/plain');
    return res.status(500).send('ERROR');
  }
}

/**
 * POST /iclock/c/cdata?SN=<SERIAL_NUMBER>&table=ATTLOG
 * Recibe cargas masivas o en tiempo real de registros de acceso y asistencia (ATTLOG / OPERLOG / BIODATA).
 */
async function handleCData(req, res, next) {
  try {
    const serialNumber = req.query.SN || req.query.sn || 'UNKNOWN_SN';
    const tableName    = req.query.table || 'ATTLOG';
    const redisClient  = req.redisClient;

    let rawBody = '';
    if (typeof req.body === 'string') {
      rawBody = req.body;
    } else if (Buffer.isBuffer(req.body)) {
      rawBody = req.body.toString('utf-8');
    } else if (typeof req.body === 'object') {
      rawBody = JSON.stringify(req.body);
    }

    logger.info(`[ADMS cdata] Recibido empuje de tabla '${tableName}' desde terminal SN=${serialNumber} (${rawBody.length} bytes)`);

    if (tableName.toUpperCase() === 'ATTLOG') {
      await zkAdmsService.processAttLogPush(serialNumber, rawBody, redisClient);
    }

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.status(200).send('OK');
  } catch (err) {
    logger.error('Error en handleCData ADMS', { error: err.message });
    res.setHeader('Content-Type', 'text/plain');
    return res.status(500).send('ERROR');
  }
}

/**
 * GET /iclock/registry?SN=<SERIAL_NUMBER>
 * Registro inicial (Handshake) de una nueva terminal biométrica al conectarse por primera vez a Railway.
 */
async function handleRegistry(req, res, next) {
  try {
    const serialNumber = req.query.SN || req.query.sn || 'UNKNOWN_SN';
    logger.info(`⚡ [ADMS Handshake] Nueva terminal SpeedFace-V5L reportándose en Railway: SN=${serialNumber}`);

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    // Parámetros de sincronización iClock: Delay=5s entre consultas, TransFlag=1 (Transmitir todo)
    return res.status(200).send(`Registry=OK\nDelay=5\nTransFlag=1\nTransTimes=00:00;14:00\nTimeZone=-6\nRealtime=1\nEncrypt=0`);
  } catch (err) {
    res.setHeader('Content-Type', 'text/plain');
    return res.status(500).send('ERROR');
  }
}

// ── 2. ENDPOINTS M2M / ADMINISTRATIVOS PARA GESTIÓN DESDE OTROS SERVICIOS ───

/**
 * POST /api/v1/adms/sync-user
 * Invocado por payment-service (al completarse un pago) o por panel admin para registrar/actualizar rostro.
 */
async function syncBiometricUser(req, res, next) {
  try {
    const { usuario_id, pin, nombre, plantilla_base64, numero_tarjeta = '', serial_number = 'ALL' } = req.body;

    if (!pin) {
      return res.status(400).json({ success: false, data: null, error: 'PIN numérico de terminal es requerido.' });
    }

    const result = await zkAdmsService.enqueueSyncUser({
      usuarioId:               usuario_id,
      pin:                     pin,
      nombre:                  nombre || `Socio-${pin}`,
      biometricTemplateBase64: plantilla_base64 || null,
      numeroTarjeta:           numero_tarjeta,
      serialNumber:            serial_number,
    }, req.redisClient);

    return res.status(200).json({
      success: true,
      data: {
        mensaje:        'Comando de sincronización facial (DATA UPDATE) encolado exitosamente.',
        user_command_id: result.userCommandId,
        bio_command_id:  result.bioCommandId,
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/adms/delete-user
 * Invocado por webhook de Stripe (al cancelarse o vencer membresía) para borrar rostro instantáneamente.
 */
async function deleteBiometricUser(req, res, next) {
  try {
    const { usuario_id, pin, serial_number = 'ALL' } = req.body;

    if (!pin) {
      return res.status(400).json({ success: false, data: null, error: 'PIN numérico de terminal es requerido para borrado.' });
    }

    const result = await zkAdmsService.enqueueDeleteUser({
      usuarioId:    usuario_id,
      pin:          pin,
      serialNumber: serial_number,
    }, req.redisClient);

    return res.status(200).json({
      success: true,
      data: {
        mensaje:           'Comandos de revocación y borrado facial (DATA DELETE) encolados para ejecución inmediata.',
        delete_bio_cmd_id:  result.deleteBioCmdId,
        delete_user_cmd_id: result.deleteUserCmdId,
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  handleGetRequest,
  handleDeviceCmd,
  handleCData,
  handleRegistry,
  syncBiometricUser,
  deleteBiometricUser,
};
