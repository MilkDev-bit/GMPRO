/**
 * @file services/access-service/src/middlewares/admsDeviceAuth.js
 * @description Autenticación de terminales biométricas ZKTeco en los endpoints /iclock/*.
 *
 * VULNERABILIDAD CORREGIDA (Crítica):
 *   Los endpoints ADMS (/iclock/getrequest, /devicecmd, /c/cdata, /registry) estaban
 *   ABIERTOS. Cualquiera podía:
 *     • GET /iclock/getrequest?SN=... → leer la cola de comandos, que incluye
 *       `DATA UPDATE BIODATA ... Tmp=<plantilla facial>` → EXFILTRACIÓN de biometría.
 *     • POST /iclock/c/cdata?table=ATTLOG → inyectar accesos falsos en el historial.
 *     • POST /iclock/devicecmd → confirmar (Return=0) borrados nunca ejecutados,
 *       dejando enrolado a un socio ya revocado.
 *
 * DEFENSA (fail-closed cuando está configurado):
 *   1. Allowlist de números de serie (ZK_ALLOWED_SERIALS): solo terminales conocidas.
 *   2. Clave de push compartida (ZK_PUSH_KEY) comparada a tiempo constante, recibida
 *      por header `x-adms-key` o query `?key=` (configurable en la URL de la terminal).
 *
 *   Si NINGUNA de las dos variables está configurada, se opera en modo legacy con una
 *   ADVERTENCIA CRÍTICA en logs (para no romper despliegues existentes), pero en
 *   producción ambas DEBEN establecerse.
 */

'use strict';

const { timingSafeEqual }     = require('crypto');
const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:admsDeviceAuth');

const ALLOWED_SERIALS = (env.ZK_ALLOWED_SERIALS || '')
  .split(',').map((s) => s.trim()).filter(Boolean);
const PUSH_KEY     = env.ZK_PUSH_KEY || null;
const PUSH_KEY_BUF = PUSH_KEY ? Buffer.from(PUSH_KEY, 'utf8') : null;

let warnedLegacy = false;

function constantTimeEquals(provided) {
  if (!PUSH_KEY_BUF || typeof provided !== 'string') return false;
  const providedBuf = Buffer.from(provided, 'utf8');
  return providedBuf.length === PUSH_KEY_BUF.length
    && timingSafeEqual(providedBuf, PUSH_KEY_BUF);
}

function requireAdmsDeviceAuth(req, res, next) {
  const serialNumber = req.query.SN || req.query.sn || null;

  // Modo legacy inseguro (sin configurar): advertir de forma prominente y permitir.
  if (ALLOWED_SERIALS.length === 0 && !PUSH_KEY) {
    if (!warnedLegacy) {
      warnedLegacy = true;
      logger.error('⚠️ ADMS /iclock SIN AUTENTICACIÓN: define ZK_ALLOWED_SERIALS y ZK_PUSH_KEY en producción. Riesgo de exfiltración de biometría.');
    }
    return next();
  }

  // 1. Allowlist de número de serie.
  if (ALLOWED_SERIALS.length > 0) {
    if (!serialNumber || !ALLOWED_SERIALS.includes(serialNumber)) {
      logger.warn('ADMS: número de serie no autorizado', { serialNumber, ip: req.ip });
      res.setHeader('Content-Type', 'text/plain');
      return res.status(403).send('UNAUTHORIZED');
    }
  }

  // 2. Clave de push compartida.
  if (PUSH_KEY) {
    const provided = req.headers['x-adms-key'] || req.query.key || req.query.pushkey;
    if (!constantTimeEquals(provided)) {
      logger.warn('ADMS: clave de push inválida o ausente', { serialNumber, ip: req.ip });
      res.setHeader('Content-Type', 'text/plain');
      return res.status(403).send('UNAUTHORIZED');
    }
  }

  req.zkDevice = { serialNumber };
  return next();
}

module.exports = { requireAdmsDeviceAuth };
