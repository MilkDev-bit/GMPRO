/**
 * @file services/access-service/src/services/zkAdmsService.js
 * @description Servicio core para el protocolo ZKTeco ADMS (Push HTTP / iClock).
 * Maneja la sincronización en la nube con terminales biométricas SpeedFace-V5L:
 *   • Carga de rostros autorizados cuando un usuario paga su membresía (DATA UPDATE BIODATA / USERINFO).
 *   • Eliminación inmediata de rostros cuando la membresía vence o falla el pago (DATA DELETE BIODATA / USERINFO).
 *   • Gestión de cola de comandos y recepción de logs de acceso en tiempo real (ATTLOG).
 */

'use strict';

const crypto                  = require('crypto');
const { createClient }        = require('@supabase/supabase-js');
const { getSupabaseClient }   = require('../config/database');
const accessModel             = require('../models/accessModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:zkAdmsService');

// Prefijo en Redis para la cola de comandos pendientes por terminal/SN
const REDIS_QUEUE_PREFIX = 'zk:adms:commands:';
// TTL para comandos pendientes en Redis (7 días antes de expirar si la terminal se apaga)
const COMMAND_TTL_SECONDS = 604_800;

// Cache en memoria de pin_terminal → UUID (se invalida cada 10 min para no sobrecargar DB)
// ACOTADO para evitar fuga de memoria en el contenedor de Railway: al superar el
// límite se evict-a la entrada más antigua (Map preserva orden de inserción).
const PIN_CACHE = new Map();
const PIN_CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutos
const PIN_CACHE_MAX    = 5000;           // Tope duro de entradas simultáneas

// Cliente separado para leer el schema auth_service_db (solo para resolver PINs de ATTLOG)
let _authDbClient = null;
function getAuthDbClient() {
  if (_authDbClient) return _authDbClient;
  const supabaseUrl     = process.env.SUPABASE_URL;
  const supabaseKey     = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    logger.warn('SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY no configurados: resolución de PIN no disponible');
    return null;
  }
  _authDbClient = createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: 'auth_service_db' },
    global: { headers: { 'x-app-name': 'gympro-access-service-pin-resolver' } },
  });
  return _authDbClient;
}

/**
 * Resuelve un pin_terminal numérico al UUID del usuario en Supabase.
 * Utiliza caché en memoria con TTL para evitar consultas repetidas en ráfagas de ATTLOG.
 *
 * @param {string|number} pin
 * @returns {Promise<string|null>} UUID del usuario o null si no se encuentra
 */
async function resolvePinToUserId(pin) {
  const pinKey = String(pin);

  // Verificar caché
  const cached = PIN_CACHE.get(pinKey);
  if (cached && (Date.now() - cached.ts) < PIN_CACHE_TTL_MS) {
    return cached.userId;
  }
  // Entrada expirada: eliminarla para no acumular basura.
  if (cached) PIN_CACHE.delete(pinKey);

  const db = getAuthDbClient();
  if (!db) return null;

  try {
    const { data, error } = await db
      .from('usuarios')
      .select('id')
      .eq('pin_terminal', parseInt(pinKey, 10))
      .is('eliminado_en', null)
      .limit(1)
      .single();

    if (error || !data) return null;

    // Guardar en caché con eviction del más antiguo si se alcanzó el tope.
    if (PIN_CACHE.size >= PIN_CACHE_MAX) {
      const oldestKey = PIN_CACHE.keys().next().value;
      if (oldestKey !== undefined) PIN_CACHE.delete(oldestKey);
    }
    PIN_CACHE.set(pinKey, { userId: data.id, ts: Date.now() });
    return data.id;
  } catch (err) {
    logger.error(`Error resolviendo PIN ${pinKey} a UUID: ${err.message}`);
    return null;
  }
}

/**
 * Genera un ID numérico secuencial/único para comandos ZKTeco (rango 1 - 2^31).
 * Las terminales SpeedFace-V5L esperan un identificador numérico en el formato C:<ID>:DATA...
 */
// Contador monotónico sembrado aleatoriamente: garantiza IDs ÚNICOS dentro del
// proceso (el esquema anterior timestamp+random podía colisionar y marcar como
// 'completed' un comando distinto en processCommandResult). Rango ZKTeco: 1..2^31-1.
let _cmdCounter = crypto.randomInt(1, 1_000_000);
function generateCommandId() {
  _cmdCounter += 1;
  if (_cmdCounter >= 2_147_483_647) _cmdCounter = 1;
  return _cmdCounter;
}

/**
 * ── 1. CARGA DE ROSTRO AUTORIZADO (DATA UPDATE USERINFO & BIODATA) ──────────
 * Encola los comandos ZKTeco necesarios para dar de alta o actualizar a un socio
 * en la memoria local de todas o una terminal biométrica SpeedFace-V5L.
 *
 * @param {object} params
 * @param {string} params.usuarioId - UUID del usuario en Supabase
 * @param {string|number} params.pin - ID numérico (PIN) corto asignado al usuario en la terminal (ej. '1042')
 * @param {string} params.nombre - Nombre legible del socio (ej. 'Carlos Mendoza')
 * @param {string} [params.biometricTemplateBase64] - Plantilla facial en Base64 (Type=9 en SpeedFace-V5L)
 * @param {string} [params.numeroTarjeta] - Número de tarjeta RFID o código QR estático si aplica
 * @param {string} [params.serialNumber='ALL'] - Número de serie de la terminal o 'ALL' para todas
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<{ userCommandId: number, bioCommandId: number|null }>}
 */
async function enqueueSyncUser({
  usuarioId,
  pin,
  nombre,
  biometricTemplateBase64 = null,
  numeroTarjeta = '',
  serialNumber = 'ALL',
}, redisClient = null) {
  const pinStr = String(pin).trim();
  const cleanName = String(nombre || 'Socio GymPro').replace(/[\t\n\r]/g, ' ');

  // 1. Comando USERINFO: Crea o actualiza los datos básicos en la tabla USER_INFO de SQLite de la terminal
  // TZ=0000000100000000 otorga acceso 24/7 (o zona horaria 1 de la terminal)
  const userCommandId = generateCommandId();
  const cmdUserInfo = `C:${userCommandId}:DATA UPDATE USERINFO PIN=${pinStr}\tName=${cleanName}\tPri=0\tPasswd=\tCard=${numeroTarjeta}\tGrp=1\tTZ=0000000100000000`;

  await _pushCommandToQueue(serialNumber, userCommandId, cmdUserInfo, {
    usuarioId, pin: pinStr, tipo: 'UPDATE_USERINFO',
  }, redisClient);

  logger.info('Comando ZKTeco encolado: DATA UPDATE USERINFO (Alta/Actualización)', {
    userCommandId, pin: pinStr, nombre: cleanName, serialNumber,
  });

  // 2. Comando BIODATA (Opcional si se proporciona la plantilla facial capturada previamente)
  // Type=9 es el identificador de Plantilla Biométrica de Rostro (SpeedFace / ZKPalm / Visible Light)
  let bioCommandId = null;
  if (biometricTemplateBase64) {
    bioCommandId = generateCommandId();
    const cmdBioData = `C:${bioCommandId}:DATA UPDATE BIODATA Pin=${pinStr}\tNo=0\tIndex=0\tType=9\tDuress=0\tTmp=${biometricTemplateBase64}`;

    await _pushCommandToQueue(serialNumber, bioCommandId, cmdBioData, {
      usuarioId, pin: pinStr, tipo: 'UPDATE_BIODATA_FACE',
    }, redisClient);

    logger.info('Comando ZKTeco encolado: DATA UPDATE BIODATA (Plantilla Facial Type=9)', {
      bioCommandId, pin: pinStr, serialNumber,
    });
  }

  return { userCommandId, bioCommandId };
}

/**
 * ── 2. ELIMINACIÓN DE ROSTRO Y ACCESO (DATA DELETE USERINFO & BIODATA) ──────
 * Encola los comandos de borrado para revocar inmediatamente el acceso y eliminar
 * el rostro de la memoria local de la terminal SpeedFace-V5L al segundo en que vence
 * la suscripción del socio o falla su cobro de Stripe.
 *
 * @param {object} params
 * @param {string} params.usuarioId - UUID del usuario en Supabase
 * @param {string|number} params.pin - ID numérico (PIN) asignado en la terminal
 * @param {string} [params.serialNumber='ALL']
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<{ deleteBioCmdId: number, deleteUserCmdId: number }>}
 */
async function enqueueDeleteUser({
  usuarioId,
  pin,
  serialNumber = 'ALL',
}, redisClient = null) {
  const pinStr = String(pin).trim();

  // 1. Primero borramos la plantilla facial (Type=9) y biométricos asociados
  const deleteBioCmdId = generateCommandId();
  const cmdDeleteBio = `C:${deleteBioCmdId}:DATA DELETE BIODATA Pin=${pinStr}\tType=9`;

  await _pushCommandToQueue(serialNumber, deleteBioCmdId, cmdDeleteBio, {
    usuarioId, pin: pinStr, tipo: 'DELETE_BIODATA_FACE',
  }, redisClient);

  // 2. Borramos al usuario de la tabla USERINFO para inactivación total física
  const deleteUserCmdId = generateCommandId();
  const cmdDeleteUser = `C:${deleteUserCmdId}:DATA DELETE USERINFO PIN=${pinStr}`;

  await _pushCommandToQueue(serialNumber, deleteUserCmdId, cmdDeleteUser, {
    usuarioId, pin: pinStr, tipo: 'DELETE_USERINFO',
  }, redisClient);

  logger.warn('⚠️ [ADMS REVOCACIÓN] Comandos de borrado encolados para terminal biometría', {
    deleteBioCmdId, deleteUserCmdId, pin: pinStr, usuarioId, serialNumber,
  });

  return { deleteBioCmdId, deleteUserCmdId };
}

/**
 * ── 3. DESPACHO DE COMANDOS PENDIENTES A LA TERMINAL (GET /iclock/getrequest) ─
 * Cuando la terminal SpeedFace-V5L consulta el servidor cada 5 segundos, esta función
 * recupera el siguiente bloque de comandos pendientes (hasta 10 comandos por petición).
 *
 * @param {string} serialNumber - Número de serie de la terminal SpeedFace-V5L
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<string>} Cadena con comandos separados por salto de línea (\n) o 'OK' si no hay pendientes
 */
async function getPendingCommandsForDevice(serialNumber, redisClient = null) {
  const queueKeys = [
    `${REDIS_QUEUE_PREFIX}${serialNumber}`, // Comandos específicos para esta terminal
    `${REDIS_QUEUE_PREFIX}ALL`,             // Comandos broadcast para todas las terminales
  ];

  const pendingCommands = [];

  if (redisClient) {
    for (const qKey of queueKeys) {
      // Extraer los primeros 10 comandos de la cola de Redis sin borrarlos (se eliminan en devicecmd al confirmar)
      const rawCmds = await redisClient.lrange(qKey, 0, 9);
      for (const itemStr of rawCmds) {
        try {
          const item = JSON.parse(itemStr);
          if (item && item.commandString) {
            pendingCommands.push(item.commandString);
          }
        } catch (_) {}
      }
    }
  } else {
    // Fallback si Redis no está disponible: consultar tabla de cola en Supabase PostgreSQL
    const db = getSupabaseClient();
    const { data, error } = await db
      .from('zk_device_commands')
      .select('id, command_id, command_string')
      .in('serial_number', [serialNumber, 'ALL'])
      .eq('estado', 'pending')
      .order('creado_at', { ascending: true })
      .limit(10);

    if (!error && data && data.length > 0) {
      data.forEach((row) => pendingCommands.push(row.command_string));
    }
  }

  if (pendingCommands.length === 0) {
    return 'OK';
  }

  logger.info(`Despachando ${pendingCommands.length} comandos ZKTeco a terminal SN=${serialNumber}`);
  // ZKTeco ADMS requiere que los comandos se envíen en líneas separadas
  return pendingCommands.join('\n');
}

/**
 * ── 4. PROCESAMIENTO DE RESPUESTA DEL HARDWARE (POST /iclock/devicecmd) ─────
 * Al completar un comando, la terminal envía un POST con ID=<command_id>&Return=<0|-1>.
 * Si Return=0, el comando se ejecutó exitosamente en la memoria del dispositivo.
 *
 * @param {string} serialNumber
 * @param {string|number} commandId
 * @param {string|number} returnCode - '0' para éxito, '-1' u otro para error
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<void>}
 */
async function processCommandResult(serialNumber, commandId, returnCode, redisClient = null) {
  const isSuccess = String(returnCode) === '0';
  logger.info('Respuesta de ejecución de comando ZKTeco recibida', {
    serialNumber, commandId, returnCode, isSuccess,
  });

  const queueKeys = [
    `${REDIS_QUEUE_PREFIX}${serialNumber}`,
    `${REDIS_QUEUE_PREFIX}ALL`,
  ];

  if (redisClient) {
    // Eliminar el comando con ID coincidente de las colas Redis
    for (const qKey of queueKeys) {
      const rawCmds = await redisClient.lrange(qKey, 0, -1);
      for (const itemStr of rawCmds) {
        try {
          const item = JSON.parse(itemStr);
          if (String(item.commandId) === String(commandId)) {
            await redisClient.lrem(qKey, 0, itemStr);
            logger.debug(`Comando ${commandId} removido de cola Redis ${qKey}`);
          }
        } catch (_) {}
      }
    }
  }

  // Sincronizar estado en PostgreSQL (tabla zk_device_commands para historial/auditoría)
  const db = getSupabaseClient();
  await db
    .from('zk_device_commands')
    .update({
      estado:        isSuccess ? 'completed' : 'failed',
      return_code:   String(returnCode),
      ejecutado_at:  new Date().toISOString(),
    })
    .eq('command_id', String(commandId));
}

/**
 * ── 5. PROCESAMIENTO DE REGISTROS BIOMÉTRICOS DE ACCESO (POST /iclock/c/cdata)
 * Cuando la terminal SpeedFace-V5L reconoce el rostro de un socio, envía un payload de texto
 * ATTLOG con el formato: PIN\tTime\tStatus\tVerifyType\tWorkCode...
 * Ejemplo: "1042\t2026-07-16 18:00:00\t0\t15\t0" (VerifyType 15 = Reconocimiento Facial)
 *
 * @param {string} serialNumber
 * @param {string} rawAttLogBody - Cuerpo en texto crudo de la petición ADMS
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<number>} Cantidad de registros de acceso procesados y guardados
 */
async function processAttLogPush(serialNumber, rawAttLogBody, redisClient = null) {
  if (!rawAttLogBody || typeof rawAttLogBody !== 'string') return 0;

  const lines = rawAttLogBody.replace(/\r/g, '').split('\n');
  let processedCount = 0;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Formato estándar ZKTeco ATTLOG: PIN \t Time \t Status \t VerifyType \t WorkCode
    const parts = trimmed.split('\t');
    if (parts.length >= 2) {
      const pin        = parts[0].trim();
      const timeStr    = parts[1].trim();
      const verifyType = parts[3] ? parseInt(parts[3], 10) : 15; // 15=Rostro, 1=Huella, 4=RFID

      // Mapeo legible del tipo biométrico para el historial en PostgreSQL
      const metodoAcceso = verifyType === 15 ? 'face_biometric' : verifyType === 4 ? 'rfid_card' : 'zk_terminal';

      try {
        // Resolver pin_terminal → UUID real del usuario (con caché para alto volumen)
        const resolvedUserId = await resolvePinToUserId(pin);
        const finalUserId    = resolvedUserId || `zk_pin_${pin}_unresolved`;

        await accessModel.recordAccess({
          usuarioId:       finalUserId,
          tokenCodigo:     `ZK-${serialNumber}-${pin}-${Date.now()}`,
          metodoAcceso:    metodoAcceso,
          accesoConcedido: true,
          razonRechazo:    null,
        }, redisClient);

        if (resolvedUserId) {
          logger.debug(`ATTLOG resuelto: PIN ${pin} → UUID ${resolvedUserId}`, { serialNumber });
        } else {
          logger.warn(`ATTLOG: PIN ${pin} sin mapeo de usuario en auth_service_db, guardado como zk_pin_${pin}_unresolved`);
        }

        processedCount++;
      } catch (err) {
        logger.error(`Error guardando ATTLOG de terminal ${serialNumber} para PIN ${pin}: ${err.message}`);
      }
    }
  }

  logger.info(`Procesados ${processedCount} registros de acceso biométrico (ATTLOG) desde SN=${serialNumber}`);
  return processedCount;
}

// ── AUXILIAR PRIVADO PARA ENCOLAR COMANDOS ──────────────────────────────────
async function _pushCommandToQueue(serialNumber, commandId, commandString, metadata, redisClient) {
  const item = {
    commandId,
    commandString,
    serialNumber,
    metadata,
    creadoAt: new Date().toISOString(),
  };

  if (redisClient) {
    const qKey = `${REDIS_QUEUE_PREFIX}${serialNumber}`;
    await redisClient.rpush(qKey, JSON.stringify(item));
    await redisClient.expire(qKey, COMMAND_TTL_SECONDS);
  }

  // Sincronizar también a PostgreSQL en segundo plano por durabilidad
  const db = getSupabaseClient();
  await db.from('zk_device_commands').insert({
    command_id:     String(commandId),
    serial_number:  serialNumber,
    command_string: commandString,
    estado:         'pending',
    metadata:       metadata,
    creado_at:      new Date().toISOString(),
  }).select('id').maybeSingle().catch((err) => {
    // Si la tabla aún no existe en entorno de dev no colapsar la sincronización en Redis
    logger.debug('Nota: No se pudo escribir en zk_device_commands de Supabase (¿tabla en creación?): ' + err.message);
  });
}

module.exports = {
  enqueueSyncUser,
  enqueueDeleteUser,
  getPendingCommandsForDevice,
  processCommandResult,
  processAttLogPush,
};
