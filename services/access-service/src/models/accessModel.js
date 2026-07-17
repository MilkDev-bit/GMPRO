/**
 * @file services/access-service/src/models/accessModel.js
 * @description Capa de acceso a datos para access_service_db (historial_accesos y tickets_visitas).
 * Implementa control de concurrencia atómico para evitar Race Conditions en validación de tickets.
 */

'use strict';

const crypto                  = require('crypto');
const { getSupabaseClient }   = require('../config/database');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:accessModel');

/**
 * Verifica si un token o nonce ya fue utilizado previamente para ingresar.
 * Previene ataques de repetición (Replay Attacks) en códigos QR dinámicos.
 *
 * @param {string} tokenCodigo
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<boolean>}
 */
async function isNonceAlreadyUsed(tokenCodigo, redisClient = null) {
  if (redisClient) {
    const usedInRedis = await redisClient.get(`access:nonce_used:${tokenCodigo}`);
    if (usedInRedis) return true;
  }

  const db = getSupabaseClient();
  const { data, error } = await db
    .from('historial_accesos')
    .select('id')
    .eq('token_codigo', tokenCodigo)
    .limit(1)
    .single();

  if (error && error.code !== 'PGRST116') throw error;
  return !!data;
}

/**
 * Registra un acceso en el historial de ingresos/egresos y marca el nonce en Redis.
 *
 * @param {object} params
 * @param {string} params.usuarioId
 * @param {string} params.tokenCodigo
 * @param {string} [params.metodoAcceso='qr'] - 'qr' | 'ticket' | 'manual'
 * @param {boolean} [params.accesoConcedido=true]
 * @param {string} [params.razonRechazo=null]
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<object>}
 */
async function recordAccess({
  usuarioId,
  tokenCodigo,
  metodoAcceso = 'qr',
  accesoConcedido = true,
  razonRechazo = null,
}, redisClient = null) {
  const db    = getSupabaseClient();
  const ahora = new Date().toISOString();

  if (redisClient && tokenCodigo) {
    await redisClient.setex(`access:nonce_used:${tokenCodigo}`, 60, '1');
  }

  const { data, error } = await db
    .from('historial_accesos')
    .insert({
      usuario_id:       usuarioId,
      fecha_hora:       ahora,
      acceso_concedido: accesoConcedido,
      razon_rechazo:    razonRechazo,
      metodo_acceso:    metodoAcceso,
      token_codigo:     tokenCodigo,
    })
    .select('*')
    .single();

  if (error) {
    logger.error('Error guardando registro en historial_accesos', { error: error.message });
    throw error;
  }

  logger.info('Registro de acceso guardado en historial', {
    id: data.id, usuarioId, accesoConcedido, metodoAcceso,
  });

  return data;
}

/**
 * Crea un nuevo ticket de visita en la tabla tickets_visitas con estado 'active'.
 *
 * @param {object} ticketData
 * @param {string} [ticketData.usuario_id]
 * @param {string} ticketData.codigo_ticket
 * @param {string} ticketData.expira_en
 * @param {string} [ticketData.notas]
 * @returns {Promise<object>}
 */
async function createTicketRecord(ticketData) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('tickets_visitas')
    .insert({
      usuario_id:    ticketData.usuario_id || null,
      codigo_ticket: ticketData.codigo_ticket,
      estado:        'active',          // Cumple Tarea 3.3: estado inicial 'active'
      expira_en:     ticketData.expira_en,
      notas:         ticketData.notas || null,
      creado_at:     new Date().toISOString(),
      usado_at:      null,
    })
    .select('*')
    .single();

  if (error) {
    logger.error('Error creando ticket_visitas en DB', { error: error.message });
    throw error;
  }

  logger.info('Ticket creado en DB con estado active', { id: data.id, codigo: data.codigo_ticket });
  return data;
}

/**
 * Busca y valida un ticket solo lectura para obtener sus metadatos e informarle al usuario por qué falló
 * en caso de estar vencido o ya usado.
 *
 * @param {string} codigoTicket
 * @returns {Promise<object|null>}
 */
async function findTicketByCode(codigoTicket) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from('tickets_visitas')
    .select('*')
    .eq('codigo_ticket', codigoTicket)
    .limit(1)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null;
    throw error;
  }
  return data;
}

/**
 * Intenta adquirir un lock distribuido (Mutex en Redis) y ejecutar un consumo atómico de ticket en DB.
 *
 * PREVENCIÓN DE RACE CONDITIONS (Condición de Carrera):
 *   Si dos torniquetes escanean exactamente el mismo código al mismo milisegundo:
 *   1. Capa Redis (Mutex distribuido): Se intenta SET lock:ticket:{codigo} NX PX 5000.
 *      Solo el primer request obtiene el lock; el segundo es rechazado de inmediato con un fallo de concurrencia.
 *   2. Capa PostgreSQL/Supabase (Check-and-Set Atómico):
 *      Ejecutamos un UPDATE condicional: UPDATE tickets_visitas SET estado = 'used', usado_at = NOW()
 *      WHERE codigo_ticket = :codigo AND estado = 'active' AND expira_en > NOW() RETURNING *.
 *      Gracias al aislamiento ACID de PostgreSQL y al bloqueo de fila (Row-Level Lock), la primera transacción en llegar
 *      actualiza la fila a 'used'. Cuando la segunda transacción intenta evaluar el WHERE, encuentra que estado != 'active'
 *      (o count 0), retornando null sin permitir una doble entrada jamás.
 *
 * @param {string} codigoTicket
 * @param {import('ioredis').Redis|null} redisClient
 * @returns {Promise<{ success: boolean, ticket: object|null, reason: string|null, isConcurrencyHit: boolean }>}
 */
async function consumeTicketAtomically(codigoTicket, redisClient = null) {
  const lockKey = `lock:ticket:${codigoTicket}`;
  const lockId  = crypto.randomUUID();

  // ── 1. Capa Redis Mutex (Redlock / Atomic SET NX PX) ──────────────────────
  if (redisClient) {
    try {
      // SET key value NX PX 5000 -> Solo establece si no existe, expira en 5s
      const acquired = await redisClient.set(lockKey, lockId, 'PX', 5000, 'NX');
      if (!acquired) {
        logger.warn('Race condition / intento simultáneo bloqueado por Mutex Redis', { codigoTicket });
        return {
          success: false,
          ticket:  null,
          reason:  'CONCURRENCY_LOCK: El ticket está siendo procesado en otro lector en este milisegundo.',
          isConcurrencyHit: true,
        };
      }
    } catch (redisErr) {
      logger.warn('Fallo adquiriendo lock en Redis, continuando con protección atómica de DB', {
        error: redisErr.message,
      });
    }
  }

  try {
    const db       = getSupabaseClient();
    const ahoraIso = new Date().toISOString();

    // ── 2. Capa DB: UPDATE atómico Check-and-Set ────────────────────────────
    // Al incluir .eq('estado', 'active') y .gt('expira_en', ahoraIso) directamente en el UPDATE,
    // PostgreSQL garantiza que la fila SOLO se modifica si está libre y vigente.
    // Soportamos tanto 'active' como 'valido' si hubieran registros antiguos.
    const { data: updatedTicket, error } = await db
      .from('tickets_visitas')
      .update({
        estado:   'used',
        usado_at: ahoraIso,
        usado_en: ahoraIso, // Alias por compatibilidad
      })
      .eq('codigo_ticket', codigoTicket)
      .in('estado', ['active', 'valido'])
      .gt('expira_en', ahoraIso)
      .select('*')
      .maybeSingle();

    if (error) {
      logger.error('Error en consumo atómico de ticket en Supabase', { error: error.message });
      throw error;
    }

    if (!updatedTicket) {
      // Si devolvió null, significa que no cumplió el WHERE (no existía, ya no estaba active o expiró).
      // Consultamos el registro en modo solo lectura para dar un mensaje de error exacto al torniquete.
      const existing = await findTicketByCode(codigoTicket);
      if (!existing) {
        return { success: false, ticket: null, reason: 'NOT_FOUND: El ticket no existe.', isConcurrencyHit: false };
      }
      if (existing.estado === 'used' || existing.estado === 'usado') {
        const usadoFecha = existing.usado_at || existing.usado_en || 'desconocida';
        return {
          success: false,
          ticket: existing,
          reason: `ALREADY_USED: Este pase ya fue utilizado anteriormente (Fecha/Hora: ${usadoFecha}).`,
          isConcurrencyHit: false,
        };
      }
      if (new Date(existing.expira_en) <= new Date()) {
        return {
          success: false,
          ticket: existing,
          reason: `EXPIRED: El ticket expiró el ${new Date(existing.expira_en).toLocaleDateString('es-MX')}.`,
          isConcurrencyHit: false,
        };
      }
      return { success: false, ticket: existing, reason: 'INVALID_STATE: El ticket no se encuentra activo.', isConcurrencyHit: false };
    }

    logger.info('CONSUMO ATÓMICO EXITOSO: Ticket pasado a estado used', {
      ticketId: updatedTicket.id,
      codigo:   updatedTicket.codigo_ticket,
      usadoAt:  updatedTicket.usado_at,
    });

    return {
      success: true,
      ticket:  updatedTicket,
      reason:  null,
      isConcurrencyHit: false,
    };
  } finally {
    // ── 3. Liberar el lock en Redis de forma segura (Script Lua para no soltar lock ajeno) ──
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
 * Reclama de forma ATÓMICA el nonce de un QR dinámico (consumo de un solo uso).
 *
 * FIX DE CONCURRENCIA (Replay / doble entrada):
 *   El control anterior (isNonceAlreadyUsed + recordAccess en pasos separados) NO
 *   era atómico: dos escaneos simultáneos del mismo QR pasaban ambos la verificación.
 *   Aquí se reclama el nonce en DOS capas, ambas atómicas:
 *     1. Redis  → SET qr:nonce:{nonce} NX PX <ttl>  (rechazo instantáneo del 2.º scan).
 *     2. DB     → INSERT en qr_nonces_consumidos (PK = nonce). Fuente de verdad
 *        durable: una violación de unicidad (23505) = replay, incluso sin Redis.
 *   Fail-closed: ante un error de DB no esperado se lanza (el caller NO concede acceso).
 *
 * @param {string} nonce
 * @param {string} usuarioId
 * @param {import('ioredis').Redis|null} redisClient
 * @param {object} [opts]
 * @param {number} [opts.claimTtlMs=40000] - Vida del lock Redis (TTL QR 30s + holgura).
 * @param {string} [opts.turnstileId]
 * @returns {Promise<{ claimed: boolean, isConcurrencyHit: boolean, layer: string|null }>}
 */
async function claimQrNonceAtomically(nonce, usuarioId, redisClient = null, opts = {}) {
  const { claimTtlMs = 40_000, turnstileId = null } = opts;

  // ── 1. Fast-path atómico en Redis ─────────────────────────────────────────
  if (redisClient) {
    try {
      const acquired = await redisClient.set(`qr:nonce:${nonce}`, usuarioId, 'PX', claimTtlMs, 'NX');
      if (!acquired) {
        return { claimed: false, isConcurrencyHit: true, layer: 'redis' };
      }
    } catch (redisErr) {
      // Redis caído: NO concedemos por Redis; la capa DB es la autoridad.
      logger.warn('Fallo reclamando nonce en Redis, usando capa DB durable', { error: redisErr.message });
    }
  }

  // ── 2. Reclamo durable en DB (autoridad, independiente de Redis) ──────────
  const db = getSupabaseClient();
  const { error } = await db
    .from('qr_nonces_consumidos')
    .insert({ nonce, usuario_id: usuarioId, turnstile_id: turnstileId });

  if (error) {
    // 23505 = unique_violation → el nonce ya fue consumido (replay atrapado).
    if (error.code === '23505') {
      return { claimed: false, isConcurrencyHit: true, layer: 'db' };
    }
    // Cualquier otro error → fail-closed (no conceder ante incertidumbre).
    logger.error('Error reclamando nonce QR en DB', { error: error.message, code: error.code });
    throw error;
  }

  return { claimed: true, isConcurrencyHit: false, layer: null };
}

module.exports = {
  isNonceAlreadyUsed,
  recordAccess,
  createTicketRecord,
  findTicketByCode,
  consumeTicketAtomically,
  claimQrNonceAtomically,
};
