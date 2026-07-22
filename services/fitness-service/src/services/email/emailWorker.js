/**
 * @file services/fitness-service/src/services/email/emailWorker.js
 * @description Worker BullMQ que consume la cola y entrega los correos.
 *
 * TOLERANCIA A FALLOS:
 *   • Errores transitorios (red, 5xx del proveedor) → se relanzan para que BullMQ
 *     reintente con backoff exponencial (5 intentos).
 *   • Errores permanentes (email inválido, plantilla rota) → se marcan como
 *     fallidos SIN reintentar (`UnrecoverableError`), evitando gastar la cola.
 *   • `concurrency` limitada para no exceder el rate limit del proveedor.
 */

'use strict';

const env = require('../../config/environment');
const emailTemplates = require('./emailTemplates');
const { sendEmail, PermanentEmailError } = require('./emailProvider');
// QUEUE_PREFIX debe importarse junto al nombre: si el worker usa un
// prefijo distinto al de la cola, escucha en otro espacio de claves de
// Redis y los jobs se acumulan sin procesarse, sin ningún error visible.
const { QUEUE_NAME, QUEUE_PREFIX, buildConnection } = require('./emailQueue');
const { createServiceLogger } = require('../../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:emailWorker');

let worker = null;
let workerConnection = null;

/**
 * Procesa un job: renderiza la plantilla y envía.
 * @param {import('bullmq').Job} job
 */
async function processJob(job) {
  const { to, template, vars } = job.data || {};
  const { UnrecoverableError } = require('bullmq');

  let rendered;
  try {
    rendered = emailTemplates.render(template, vars || {});
  } catch (err) {
    // Plantilla inexistente/rota: reintentar no sirve de nada.
    throw new UnrecoverableError(`Plantilla inválida: ${err.message}`);
  }

  try {
    const result = await sendEmail({
      to,
      subject: rendered.subject,
      html: rendered.html,
    });
    logger.info('Correo procesado', {
      jobId: job.id, to, template, providerId: result.id, simulated: result.simulated,
    });
    return result;
  } catch (err) {
    if (err instanceof PermanentEmailError) {
      throw new UnrecoverableError(err.message); // no reintentar
    }
    throw err; // transitorio → BullMQ reintenta con backoff
  }
}

/**
 * Arranca el worker. Idempotente: si ya está arrancado, no crea otro.
 * @returns {import('bullmq').Worker|null}
 */
function startEmailWorker() {
  if (worker) return worker;
  if (!env.REDIS_URL) {
    logger.warn('REDIS_URL ausente: no se arranca el worker de correos (modo directo).');
    return null;
  }

  const { Worker } = require('bullmq');
  workerConnection = buildConnection();

  worker = new Worker(QUEUE_NAME, processJob, {
    connection: workerConnection,
    prefix: QUEUE_PREFIX, // debe coincidir con el de la Queue
    concurrency: parseInt(env.EMAIL_WORKER_CONCURRENCY || '5', 10),
    // Límite defensivo para respetar la cuota del proveedor.
    limiter: { max: 10, duration: 1000 },
  });

  worker.on('failed', (job, err) => {
    logger.error('Job de correo fallido', {
      jobId: job?.id,
      to: job?.data?.to,
      template: job?.data?.template,
      attempts: job?.attemptsMade,
      error: err?.message,
    });
  });

  worker.on('completed', (job) => {
    logger.debug('Job de correo completado', { jobId: job.id });
  });

  logger.info('Worker de correos BullMQ activo', {
    queue: QUEUE_NAME,
    prefix: QUEUE_PREFIX,
  });
  return worker;
}

/** Cierre ordenado: espera a que terminen los jobs en vuelo. */
async function stopEmailWorker() {
  try {
    if (worker) await worker.close();
    if (workerConnection) await workerConnection.quit();
  } catch (err) {
    logger.warn('Error cerrando el worker de correos', { error: err.message });
  } finally {
    worker = null;
    workerConnection = null;
  }
}

module.exports = { startEmailWorker, stopEmailWorker };
