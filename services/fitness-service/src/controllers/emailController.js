/**
 * @file services/fitness-service/src/controllers/emailController.js
 * @description Endpoint interno M2M para encolar correos transaccionales.
 * Otros servicios (ai-service, payment-service) o el propio fitness-service
 * disparan correos sin conocer el proveedor ni la cola.
 */

'use strict';

const env = require('../config/environment');
const { enqueueEmail } = require('../services/email/emailQueue');
const { TEMPLATE_NAMES } = require('../services/email/emailTemplates');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:emailController');

/**
 * POST /api/v1/internal/emails/enqueue
 * Body: { to, template, vars?, delayMs?, dedupeKey? }
 *
 * Responde 202 (Accepted): el correo se entrega de forma asíncrona.
 */
async function enqueueTransactionalEmail(req, res, next) {
  try {
    const { to, template, vars = {}, delayMs = 0, dedupeKey } = req.body || {};

    if (!to || !template) {
      return res.status(400).json({
        success: false, data: null,
        error: 'Los campos "to" y "template" son obligatorios.',
      });
    }
    if (!TEMPLATE_NAMES.includes(template)) {
      return res.status(422).json({
        success: false, data: null,
        error: `Plantilla desconocida "${template}". Disponibles: ${TEMPLATE_NAMES.join(', ')}`,
      });
    }

    // La URL de la app se inyecta aquí para que los servicios no la repitan.
    const result = await enqueueEmail({
      to,
      template,
      vars: { appUrl: env.APP_DEEPLINK_URL, ...vars },
      delayMs: Number(delayMs) || 0,
      dedupeKey,
    });

    logger.info('Solicitud de correo aceptada', { to, template, ...result });

    return res.status(202).json({
      success: true,
      data: { aceptado: true, ...result },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

/** GET /api/v1/internal/emails/templates — catálogo de plantillas disponibles. */
async function listTemplates(_req, res) {
  return res.status(200).json({
    success: true,
    data: { plantillas: TEMPLATE_NAMES },
    error: null,
  });
}

module.exports = { enqueueTransactionalEmail, listTemplates };
