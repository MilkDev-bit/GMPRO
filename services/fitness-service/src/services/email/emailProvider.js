/**
 * @file services/fitness-service/src/services/email/emailProvider.js
 * @description Adaptador del proveedor de correo (Resend). Aislado a propósito
 * para que la cola no dependa del SDK concreto: cambiar de Resend a otro
 * proveedor solo toca este archivo.
 *
 * Si RESEND_API_KEY no está configurada, entra en MODO SIMULACIÓN (loguea el
 * correo) — útil en desarrollo y en CI sin credenciales reales.
 */

'use strict';

const env = require('../../config/environment');
const { createServiceLogger } = require('../../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:emailProvider');

let resendClient = null;
if (env.RESEND_API_KEY) {
  const { Resend } = require('resend');
  resendClient = new Resend(env.RESEND_API_KEY);
  logger.info('Resend inicializado para correos transaccionales');
} else {
  logger.warn('RESEND_API_KEY ausente: los correos se simularán en consola.');
}

/**
 * Error que SÍ debe reintentarse (fallo transitorio de red/proveedor).
 */
class RetriableEmailError extends Error {
  constructor(message) {
    super(message);
    this.name = 'RetriableEmailError';
    this.retriable = true;
  }
}

/**
 * Error permanente (dirección inválida, plantilla mal formada): NO reintentar.
 */
class PermanentEmailError extends Error {
  constructor(message) {
    super(message);
    this.name = 'PermanentEmailError';
    this.retriable = false;
  }
}

const EMAIL_RE = /^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$/;

/**
 * Envía un correo. Lanza errores tipados para que el worker decida si reintentar.
 *
 * @param {object} params
 * @param {string} params.to
 * @param {string} params.subject
 * @param {string} params.html
 * @param {string} [params.replyTo]
 * @returns {Promise<{ id: string|null, simulated: boolean }>}
 */
async function sendEmail({ to, subject, html, replyTo }) {
  if (!to || !EMAIL_RE.test(String(to))) {
    throw new PermanentEmailError(`Destinatario inválido: "${to}"`);
  }
  if (!subject || !html) {
    throw new PermanentEmailError('subject y html son obligatorios.');
  }

  // Modo simulación (sin credenciales).
  if (!resendClient) {
    logger.info('[EMAIL SIMULADO]', { to, subject, bytes: html.length });
    return { id: null, simulated: true };
  }

  try {
    const { data, error } = await resendClient.emails.send({
      from: `${env.EMAIL_FROM_NAME} <${env.EMAIL_FROM}>`,
      to: [to],
      subject,
      html,
      ...(replyTo ? { replyTo } : {}),
    });

    if (error) {
      // Resend devuelve error estructurado; 4xx de validación = permanente.
      const msg = error.message || 'Error desconocido de Resend';
      const isValidation = /invalid|not found|unprocessable|domain/i.test(msg);
      throw isValidation
        ? new PermanentEmailError(msg)
        : new RetriableEmailError(msg);
    }

    logger.info('Correo entregado al proveedor', { to, subject, id: data?.id });
    return { id: data?.id ?? null, simulated: false };
  } catch (err) {
    if (err instanceof PermanentEmailError || err instanceof RetriableEmailError) {
      throw err;
    }
    // Fallos de red/timeout → reintentables.
    throw new RetriableEmailError(err.message);
  }
}

module.exports = {
  sendEmail,
  RetriableEmailError,
  PermanentEmailError,
  isSimulationMode: () => resendClient === null,
};
