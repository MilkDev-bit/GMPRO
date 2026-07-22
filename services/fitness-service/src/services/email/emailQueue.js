/**
 * @file services/fitness-service/src/services/email/emailQueue.js
 * @description Cola de correos con BullMQ + Redis (productor).
 *
 * POR QUÉ UNA COLA:
 *   Enviar el correo dentro del request HTTP bloquea la respuesta y, si el
 *   proveedor tarda o falla, el usuario se come la latencia o pierde el correo.
 *   Con BullMQ el endpoint solo ENCOLA (milisegundos) y un worker independiente
 *   entrega, con reintentos exponenciales y tolerancia a caídas del proveedor.
 *
 * DEGRADACIÓN: si no hay REDIS_URL, `enqueueEmail` hace un envío directo
 * best-effort (no se pierde el correo en entornos sin Redis, p. ej. desarrollo).
 */

'use strict';

const env = require('../../config/environment');
const emailTemplates = require('./emailTemplates');
const { createServiceLogger } = require('../../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:emailQueue');

/**
 * NOMBRE Y PREFIJO DE LA COLA
 *
 * BullMQ (>= v4) RECHAZA nombres de cola que contengan ":" — lanza
 * "Queue name cannot contain :" en el constructor. El motivo es que
 * BullMQ usa ":" como separador de sus claves en Redis
 * (<prefix>:<queue>:<jobId>), así que un ":" en el nombre corrompería
 * el espacio de claves.
 *
 * El namespace va en `prefix`, que existe justo para esto.
 *
 * ⚠ `QUEUE_PREFIX` debe ser IDÉNTICO en Queue y en Worker. Si divergen,
 * el worker escucha en otro espacio de claves y los jobs se encolan sin
 * que nadie los procese: un fallo silencioso, sin error visible.
 */
const QUEUE_NAME = 'emails';
const QUEUE_PREFIX = 'gympro';

let queue = null;
let connection = null;

/**
 * Opciones de conexión a Redis para BullMQ.
 * `maxRetriesPerRequest: null` es REQUISITO de BullMQ (bloqueo de comandos).
 */
function buildConnection() {
  if (!env.REDIS_URL) return null;
  const IORedis = require('ioredis');
  return new IORedis(env.REDIS_URL, {
    maxRetriesPerRequest: null,
    enableReadyCheck: false,
  });
}

/**
 * Devuelve (creando si hace falta) la cola de correos.
 * @returns {import('bullmq').Queue|null}
 */
function getQueue() {
  if (queue) return queue;
  connection = buildConnection();
  if (!connection) {
    logger.warn('REDIS_URL ausente: la cola de correos operará en modo directo.');
    return null;
  }
  const { Queue } = require('bullmq');
  queue = new Queue(QUEUE_NAME, {
    connection,
    prefix: QUEUE_PREFIX,
    defaultJobOptions: {
      // 5 intentos con backoff exponencial: 2s, 4s, 8s, 16s…
      attempts: 5,
      backoff: { type: 'exponential', delay: 2000 },
      // Higiene: no dejar que Redis crezca sin control.
      removeOnComplete: { age: 3600, count: 1000 },
      removeOnFail: { age: 24 * 3600 },
    },
  });
  logger.info('Cola de correos BullMQ inicializada', {
    queue: QUEUE_NAME,
    prefix: QUEUE_PREFIX,
  });
  return queue;
}

/**
 * Encola un correo transaccional a partir de una plantilla.
 *
 * @param {object} params
 * @param {string} params.to            - Destinatario.
 * @param {string} params.template      - Nombre de plantilla (ver emailTemplates).
 * @param {Record<string,any>} [params.vars] - Variables a inyectar.
 * @param {number} [params.delayMs=0]   - Retraso (p. ej. recordatorios).
 * @param {string} [params.dedupeKey]   - Clave de idempotencia (evita duplicados).
 * @returns {Promise<{ queued: boolean, jobId?: string, simulatedDirect?: boolean }>}
 */
async function enqueueEmail({ to, template, vars = {}, delayMs = 0, dedupeKey }) {
  // Validación temprana: si la plantilla no existe, fallar YA (no en el worker).
  if (!emailTemplates.TEMPLATE_NAMES.includes(template)) {
    throw new Error(`Plantilla desconocida: "${template}"`);
  }

  const q = getQueue();

  // Sin Redis → envío directo best-effort para no perder el correo.
  if (!q) {
    const { sendEmail } = require('./emailProvider');
    const { subject, html } = emailTemplates.render(template, vars);
    try {
      await sendEmail({ to, subject, html });
      return { queued: false, simulatedDirect: true };
    } catch (err) {
      logger.error('Envío directo falló (sin cola)', { to, template, error: err.message });
      return { queued: false, simulatedDirect: true };
    }
  }

  const job = await q.add(
    template,
    { to, template, vars },
    {
      delay: delayMs > 0 ? delayMs : undefined,
      // jobId estable = idempotencia: reencolar el mismo hito no duplica el correo.
      ...(dedupeKey ? { jobId: dedupeKey } : {}),
    },
  );

  logger.info('Correo encolado', { to, template, jobId: job.id, delayMs });
  return { queued: true, jobId: String(job.id) };
}

/** Cierre ordenado (SIGTERM en Railway). */
async function closeQueue() {
  try {
    if (queue) await queue.close();
    if (connection) await connection.quit();
  } catch (err) {
    logger.warn('Error cerrando la cola de correos', { error: err.message });
  } finally {
    queue = null;
    connection = null;
  }
}

module.exports = {
  enqueueEmail,
  getQueue,
  closeQueue,
  QUEUE_NAME,
  QUEUE_PREFIX,
  buildConnection,
};
