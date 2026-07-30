/**
 * @file services/access-service/src/models/accessModel.js
 * @description Capa de datos para access_service_db (historial_accesos, tickets_visitas,
 * qr_nonces_consumidos). Control de concurrencia atómico anti-replay/doble-entrada.
 * Mínimo privilegio (CLD-1): pg con rol svc_access, SQL parametrizado.
 */

'use strict';

const crypto                  = require('crypto');
const { query }               = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:accessModel');

/** ¿Un token/nonce ya se usó para ingresar? (anti-replay). @returns {Promise<boolean>} */
async function isNonceAlreadyUsed(tokenCodigo, redisClient = null) {
  if (redisClient) {
    const usedInRedis = await redisClient.get(`access:nonce_used:${tokenCodigo}`);
    if (usedInRedis) return true;
  }
  const { rows } = await query(
    `SELECT id FROM historial_accesos WHERE token_codigo = $1 LIMIT 1`,
    [tokenCodigo],
  );
  return rows.length > 0;
}

/** Registra un acceso en el historial y marca el nonce en Redis. @returns {Promise<object>} */
async function recordAccess({
  usuarioId,
  tokenCodigo,
  metodoAcceso = 'qr',
  accesoConcedido = true,
  razonRechazo = null,
}, redisClient = null) {
  const ahora = new Date().toISOString();

  if (redisClient && tokenCodigo) {
    await redisClient.setex(`access:nonce_used:${tokenCodigo}`, 60, '1');
  }

  const { rows } = await query(
    `INSERT INTO historial_accesos
       (usuario_id, fecha_hora, acceso_concedido, razon_rechazo, metodo_acceso, token_codigo)
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING *`,
    [usuarioId, ahora, accesoConcedido, razonRechazo, metodoAcceso, tokenCodigo],
  );
  const data = rows[0];
  logger.info('Registro de acceso guardado en historial', {
    id: data.id, usuarioId, accesoConcedido, metodoAcceso,
  });
  return data;
}

/** Crea un ticket de visita con estado 'active'. @returns {Promise<object>} */
async function createTicketRecord(ticketData) {
  const { rows } = await query(
    `INSERT INTO tickets_visitas
       (usuario_id, codigo_ticket, estado, expira_en, notas, creado_at, usado_at)
     VALUES ($1,$2,'active',$3,$4,$5,NULL)
     RETURNING *`,
    [
      ticketData.usuario_id || null,
      ticketData.codigo_ticket,
      ticketData.expira_en,
      ticketData.notas || null,
      new Date().toISOString(),
    ],
  );
  logger.info('Ticket creado en DB con estado active', { id: rows[0].id, codigo: rows[0].codigo_ticket });
  return rows[0];
}

/** Busca un ticket por su código (solo lectura). @returns {Promise<object|null>} */
async function findTicketByCode(codigoTicket) {
  const { rows } = await query(
    `SELECT * FROM tickets_visitas WHERE codigo_ticket = $1 LIMIT 1`,
    [codigoTicket],
  );
  return rows[0] || null;
}

/**
 * Consumo ATÓMICO de ticket (Redis mutex + UPDATE check-and-set en Postgres).
 * @returns {Promise<{ success:boolean, ticket:object|null, reason:string|null, isConcurrencyHit:boolean }>}
 */
async function consumeTicketAtomically(codigoTicket, redisClient = null) {
  const lockKey = `lock:ticket:${codigoTicket}`;
  const lockId  = crypto.randomUUID();

  // ── 1. Mutex Redis (SET NX PX) ────────────────────────────────────────────
  if (redisClient) {
    try {
      const acquired = await redisClient.set(lockKey, lockId, 'PX', 5000, 'NX');
      if (!acquired) {
        logger.warn('Race condition / intento simultáneo bloqueado por Mutex Redis', { codigoTicket });
        return {
          success: false, ticket: null,
          reason: 'CONCURRENCY_LOCK: El ticket está siendo procesado en otro lector en este milisegundo.',
          isConcurrencyHit: true,
        };
      }
    } catch (redisErr) {
      logger.warn('Fallo adquiriendo lock en Redis, continuando con protección atómica de DB', { error: redisErr.message });
    }
  }

  try {
    const ahoraIso = new Date().toISOString();

    // ── 2. UPDATE atómico check-and-set ─────────────────────────────────────
    const { rows } = await query(
      `UPDATE tickets_visitas
         SET estado = 'used', usado_at = $2, usado_en = $2
       WHERE codigo_ticket = $1 AND estado IN ('active','valido') AND expira_en > $2
       RETURNING *`,
      [codigoTicket, ahoraIso],
    );
    const updatedTicket = rows[0];

    if (!updatedTicket) {
      // No cumplió el WHERE: no existía / ya no estaba active / expiró. Consultamos para el mensaje.
      const existing = await findTicketByCode(codigoTicket);
      if (!existing) {
        return { success: false, ticket: null, reason: 'NOT_FOUND: El ticket no existe.', isConcurrencyHit: false };
      }
      if (existing.estado === 'used' || existing.estado === 'usado') {
        const usadoFecha = existing.usado_at || existing.usado_en || 'desconocida';
        return {
          success: false, ticket: existing,
          reason: `ALREADY_USED: Este pase ya fue utilizado anteriormente (Fecha/Hora: ${usadoFecha}).`,
          isConcurrencyHit: false,
        };
      }
      if (new Date(existing.expira_en) <= new Date()) {
        return {
          success: false, ticket: existing,
          reason: `EXPIRED: El ticket expiró el ${new Date(existing.expira_en).toLocaleDateString('es-MX')}.`,
          isConcurrencyHit: false,
        };
      }
      return { success: false, ticket: existing, reason: 'INVALID_STATE: El ticket no se encuentra activo.', isConcurrencyHit: false };
    }

    logger.info('CONSUMO ATÓMICO EXITOSO: Ticket pasado a estado used', {
      ticketId: updatedTicket.id, codigo: updatedTicket.codigo_ticket, usadoAt: updatedTicket.usado_at,
    });
    return { success: true, ticket: updatedTicket, reason: null, isConcurrencyHit: false };
  } finally {
    // ── 3. Liberar el lock (Lua para no soltar lock ajeno) ──────────────────
    if (redisClient) {
      try {
        const luaScript = `
          if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
          else
            return 0
          end
        `;
        await redisClient.eval(luaScript, 1, lockKey, lockId);
      } catch (unlockErr) {
        logger.warn('Error liberando lock de ticket en Redis', { error: unlockErr.message });
      }
    }
  }
}

/**
 * Reclama ATÓMICAMENTE el nonce de un QR (un solo uso). Redis + DB (PK = nonce).
 * @returns {Promise<{ claimed:boolean, isConcurrencyHit:boolean, layer:string|null }>}
 */
async function claimQrNonceAtomically(nonce, usuarioId, redisClient = null, opts = {}) {
  const { claimTtlMs = 40_000, turnstileId = null } = opts;

  if (redisClient) {
    try {
      const acquired = await redisClient.set(`qr:nonce:${nonce}`, usuarioId, 'PX', claimTtlMs, 'NX');
      if (!acquired) {
        return { claimed: false, isConcurrencyHit: true, layer: 'redis' };
      }
    } catch (redisErr) {
      logger.warn('Fallo reclamando nonce en Redis, usando capa DB durable', { error: redisErr.message });
    }
  }

  // Reclamo durable en DB (autoridad). 23505 = ya consumido (replay).
  try {
    await query(
      `INSERT INTO qr_nonces_consumidos (nonce, usuario_id, turnstile_id) VALUES ($1,$2,$3)`,
      [nonce, usuarioId, turnstileId],
    );
    return { claimed: true, isConcurrencyHit: false, layer: null };
  } catch (error) {
    if (error.code === '23505') {
      return { claimed: false, isConcurrencyHit: true, layer: 'db' };
    }
    logger.error('Error reclamando nonce QR en DB', { error: error.message, code: error.code });
    throw error;
  }
}

module.exports = {
  isNonceAlreadyUsed,
  recordAccess,
  createTicketRecord,
  findTicketByCode,
  consumeTicketAtomically,
  claimQrNonceAtomically,
};
