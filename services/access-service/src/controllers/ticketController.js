/**
 * @file services/access-service/src/controllers/ticketController.js
 * @description Controladores para creación e impresión de pases únicos (/create-ticket)
 * y validación atómica en torniquete (/validate-ticket) con bloqueo contra Race Conditions.
 *
 * CUMPLE CON TAREA 3.3:
 *   • /create-ticket: Genera token aleatorio cripto-seguro, registra en tickets_visitas con estado 'active'
 *     y devuelve el string para impresión en código QR físico.
 *   • /validate-ticket: Recibe token escaneado. Verifica existencia y estado 'active'. Abre el circuito
 *     y cambia inmediatamente a 'used' con marca en usado_at. Control de concurrencia con Mutex Redis/DB.
 */

'use strict';

const crypto                  = require('crypto');
const accessModel             = require('../models/accessModel');
const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:ticketController');

// ── POST /create-ticket (o /api/v1/create-ticket, /api/v1/tickets/create) ────
/**
 * Genera un ticket de visita (pase único de un solo uso) para impresión física o envío al móvil.
 */
async function createTicket(req, res, next) {
  try {
    const { usuario_id = null, vigencia_horas = 24, notas = null, prefijo = 'GP' } = req.body;

    // ── BOLA / autorización horizontal (OWASP API #1) ────────────────────────
    // Este endpoint emite un pase de acceso físico (bearer credential para el
    // torniquete) y estampa `usuario_id` en el ticket y en el historial de
    // accesos. Bajo `jwtVerify` (cualquier rol), un socio podía suministrar el
    // usuario_id de OTRA persona → generar pases atribuidos a un tercero
    // (log-poisoning / suplantación) y emitir pases indiscriminadamente.
    //
    // Regla: solo 'admin'/'recepcion' (staff) pueden emitir un pase para un
    // usuario_id ESPECÍFICO distinto del propio. Cualquier otro caller queda
    // limitado a: (a) pase de invitado genérico (usuario_id = null) o (b) un
    // pase para SÍ MISMO. Nunca puede estampar el id de otro socio.
    // Roles internos externalizados (env.STAFF_ROLES, fallback 'staff','admin').
    // Se compara en minúsculas para tolerar variaciones de configuración.
    const isStaff = env.STAFF_ROLES.includes(String(req.user?.role || '').toLowerCase());
    const targetUsuarioId =
      usuario_id && usuario_id !== req.user.id
        ? (isStaff ? usuario_id : undefined)
        : usuario_id; // null (invitado) o el propio id: siempre permitido

    if (targetUsuarioId === undefined) {
      logger.warn('Intento de emitir ticket a nombre de otro usuario sin rol staff', {
        callerId: req.user.id, callerRole: req.user?.role, usuarioIdSolicitado: usuario_id,
      });
      return res.status(403).json({
        success: false, data: null,
        error: 'No autorizado para emitir un pase a nombre de otro usuario.',
      });
    }

    // 1. Generar token aleatorio criptográficamente seguro (alta entropía, fácil de leer y escanear)
    // Ejemplo de formato: GP-8F3A9D1B4E2C o un string hexadecimal puros
    const randomBytes  = crypto.randomBytes(8).toString('hex').toUpperCase();
    const codigoTicket = `${prefijo.toUpperCase()}-${randomBytes.substring(0, 4)}-${randomBytes.substring(4, 8)}-${randomBytes.substring(8, 12)}`;

    const ahora    = new Date();
    const expiraEn = new Date(ahora.getTime() + vigencia_horas * 60 * 60 * 1000).toISOString();

    // 2. Registrar en la base de datos con estado estrictamente 'active' y usado_at: null
    const ticket = await accessModel.createTicketRecord({
      usuario_id:    targetUsuarioId, // validado contra req.user.id / rol staff
      codigo_ticket: codigoTicket,
      expira_en:     expiraEn,
      notas:         notas,
    });

    logger.info('Ticket único de visita emitido exitosamente', {
      ticketId: ticket.id,
      codigo:   ticket.codigo_ticket,
      expiraEn,
    });

    // 3. Devolver el string para que la sucursal lo imprima en un QR físico o papel
    return res.status(201).json({
      success: true,
      data: {
        id:            ticket.id,
        codigo_ticket: ticket.codigo_ticket,
        qr_string:     ticket.codigo_ticket, // Cadena lista para alimentar a un generador de QR óptico
        estado:        ticket.estado,        // 'active'
        creado_at:     ticket.creado_at,
        expira_en:     ticket.expira_en,
        usado_at:      ticket.usado_at,      // null
        notas:         ticket.notas,
        instrucciones: 'Presente este código QR en la lectora del torniquete para un (1) solo ingreso antes de su expiración.',
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── POST /validate-ticket (o /api/v1/validate-ticket, /api/v1/tickets/validate) ──
/**
 * Valida y consume de forma atómica un ticket escaneado en el torniquete.
 * Previene Race Conditions mediante locks distribuidos y Check-and-Set en DB.
 */
async function validateTicket(req, res, next) {
  try {
    const { codigo_ticket, token } = req.body;
    const tokenAValidar = codigo_ticket || token;

    if (!tokenAValidar) {
      return res.status(400).json({
        success: false,
        data: { acceso_concedido: false, apertura_torniquete: false },
        error: 'El código del ticket o token (codigo_ticket / token) es requerido.',
      });
    }

    const codigoLimpio = tokenAValidar.trim().toUpperCase();

    // 1. Ejecutar consumo atómico con Mutex Redis + UPDATE Check-and-Set en PostgreSQL
    const result = await accessModel.consumeTicketAtomically(codigoLimpio, req.redisClient);

    // 2. Manejar casos de rechazo con códigos exactos y claros para el hardware y la recepción
    if (!result.success) {
      // Registrar el intento fallido en historial de accesos para auditoría de seguridad
      await accessModel.recordAccess({
        usuarioId:       result.ticket?.usuario_id || 'visita_generica',
        tokenCodigo:     codigoLimpio,
        metodoAcceso:    'ticket',
        accesoConcedido: false,
        razonRechazo:    result.reason,
      }, req.redisClient);

      if (result.isConcurrencyHit) {
        // HTTP 409 Conflict: dos torniquetes intentaron leer al mismo tiempo el mismo boleto
        return res.status(409).json({
          success: false,
          data: {
            acceso_concedido:    false,
            apertura_torniquete: false,
            codigo_ticket:       codigoLimpio,
            motivo_bloqueo:      'CONCURRENCY_CONFLICT',
          },
          error: result.reason,
        });
      }

      // HTTP 403 Forbidden para boletos usados, expirados o inexistentes
      return res.status(403).json({
        success: false,
        data: {
          acceso_concedido:    false,
          apertura_torniquete: false,
          codigo_ticket:       codigoLimpio,
          estado_actual:       result.ticket?.estado || 'invalid',
          usado_at:            result.ticket?.usado_at || null,
        },
        error: result.reason,
      });
    }

    // 3. Si result.success === true, la fila cambió de 'active' a 'used' con usado_at en este milisegundo exacto
    const ticketConsumido = result.ticket;

    // Registrar en historial_accesos de la base de datos
    await accessModel.recordAccess({
      usuarioId:       ticketConsumido.usuario_id || 'visita_generica',
      tokenCodigo:     codigoLimpio,
      metodoAcceso:    'ticket',
      accesoConcedido: true,
      razonRechazo:    null,
    }, req.redisClient);

    logger.info('TICKET CONSUMIDO Y ACCESO CONCEDIDO ATÓMICAMENTE', {
      ticketId: ticketConsumido.id,
      codigo:   ticketConsumido.codigo_ticket,
      usadoAt:  ticketConsumido.usado_at,
    });

    return res.status(200).json({
      success: true,
      data: {
        acceso_concedido:    true,
        apertura_torniquete: true,
        codigo_ticket:       ticketConsumido.codigo_ticket,
        estado:              ticketConsumido.estado,    // 'used'
        usado_at:            ticketConsumido.usado_at,  // ISO Timestamp
        tiempo_procesado:    new Date().toISOString(),
        mensaje:             '¡Pase de visita validado y consumido! Bienvenido a GymPro.',
      },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  createTicket,
  validateTicket,
};
