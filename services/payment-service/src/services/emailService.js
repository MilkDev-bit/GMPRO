/**
 * @file services/payment-service/src/services/emailService.js
 * @description Envío de emails automatizados de Growth (retención de usuarios,
 * reactivación deportiva e invitaciones de pago) vía Resend o simulación en consola.
 */

'use strict';

const env = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:growthEmailService');

let resendClient = null;
if (env.RESEND_API_KEY) {
  try {
    const { Resend } = require('resend');
    resendClient = new Resend(env.RESEND_API_KEY);
    logger.info('Resend growth email client inicializado');
  } catch (err) {
    logger.warn('No se pudo cargar resend, emails en consola:', err.message);
  }
} else {
  logger.warn('RESEND_API_KEY no configurado en payment-service. Emails en consola.');
}

/**
 * Envío base genérico.
 */
async function send({ to, subject, html }) {
  if (!resendClient) {
    logger.info('[GROWTH EMAIL SIMULADO]', { to, subject, preview: html.substring(0, 120) });
    return true;
  }

  try {
    const { error } = await resendClient.emails.send({
      from:    `${env.EMAIL_FROM_NAME || 'GymPro Growth'} <${env.EMAIL_FROM || 'growth@tugimnasio.com'}>`,
      to:      [to],
      subject,
      html,
    });

    if (error) throw new Error(error.message);
    logger.info('Email de retención enviado exitosamente', { to, subject });
    return true;
  } catch (err) {
    logger.error('Fallo al enviar email de retención', { to, subject, error: err.message });
    return false;
  }
}

/**
 * Envía el email motivacional de reactivación tras 5 días de inactividad,
 * incluyendo una rutina suave personalizada generada por la IA.
 *
 * @param {object} params
 * @param {string} params.email - Email del socio
 * @param {string} params.nombre - Nombre del socio
 * @param {string} params.rutinaHtml - Rutina motivacional redactada por IA
 * @param {string} [params.deepLink] - Deep link para abrir la app
 */
async function sendReactivationEmail({ email, nombre, rutinaHtml, deepLink = 'gympro://workout/reactivation' }) {
  await send({
    to: email,
    subject: `⚡ ${nombre}, ¡tu cuerpo echa de menos el movimiento! Rutina suave de regreso`,
    html: `
      <div style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; background: #0D0A1A; color: #FFFFFF; padding: 32px; border-radius: 16px;">
        <div style="text-align: center; margin-bottom: 24px;">
          <span style="background: #FF007A; color: #FFFFFF; font-size: 11px; font-weight: bold; letter-spacing: 2px; padding: 6px 14px; border-radius: 20px; text-transform: uppercase;">
            REACTIVACIÓN VIP
          </span>
        </div>
        
        <h1 style="color: #00F0FF; font-size: 24px; font-weight: 800; text-align: center; margin-bottom: 16px;">
          ¡Te extrañamos en GymPro, ${nombre}! 💪
        </h1>
        
        <p style="color: #CCCCCC; font-size: 15px; line-height: 1.6; text-align: center;">
          Han pasado <strong style="color: #FF007A;">5 días</strong> desde tu último entrenamiento. Sabemos que la vida, el trabajo o el cansancio se interponen, ¡y es totalmente normal! Lo importante es regresar sin presiones.
        </p>

        <div style="background: #151226; border: 1px solid rgba(0, 240, 255, 0.2); border-radius: 12px; padding: 20px; margin: 24px 0;">
          <h2 style="color: #00F0FF; font-size: 16px; font-weight: bold; margin-top: 0; margin-bottom: 12px; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 8px;">
            🧘 Tu Rutina de Reactivación Suave (20 Minutos)
          </h2>
          <div style="color: #E0E0E0; font-size: 14px; line-height: 1.6;">
            ${rutinaHtml || '<p>1. Calentamiento articular (5 min)<br>2. 3 series de sentadillas con peso corporal (12 reps)<br>3. 3 series de caminadora suave en pendiente (10 min)</p>'}
          </div>
        </div>

        <div style="text-align: center; margin: 32px 0;">
          <a href="${deepLink}"
             style="background: linear-gradient(135deg, #FF007A 0%, #9D00FF 100%); color: #FFFFFF; padding: 16px 32px; border-radius: 30px; text-decoration: none; font-weight: bold; font-size: 15px; display: inline-block; box-shadow: 0 8px 24px rgba(255, 0, 122, 0.4);">
            🚀 Empezar Rutina Suave Ahora
          </a>
        </div>

        <hr style="border: none; border-top: 1px solid #2A2640; margin: 28px 0;">
        
        <p style="color: #666666; font-size: 12px; text-align: center; margin: 0;">
          GymPro App • Inteligencia Artificial Aplicada al Rendimiento<br>
          Si no deseas recibir más alertas de motivación, puedes ajustar tus preferencias en la app.
        </p>
      </div>
    `,
  });
}

/**
 * Envía email de recuperación de pago fallido o vencido (`past_due`).
 *
 * @param {object} params
 * @param {string} params.email
 * @param {string} params.nombre
 * @param {string} params.planNombre
 * @param {number} params.monto
 * @param {string} [params.deepLink]
 */
async function sendPaymentRecoveryEmail({ email, nombre, planNombre, monto, deepLink = 'gympro://settings/billing' }) {
  await send({
    to: email,
    subject: `⚠️ ${nombre}, acción requerida: actualiza tu método de pago en GymPro`,
    html: `
      <div style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; background: #0D0A1A; color: #FFFFFF; padding: 32px; border-radius: 16px;">
        <h1 style="color: #FF007A; font-size: 22px; font-weight: 800; text-align: center;">
          Tu membresía ${planNombre || 'GymPro'} está pendiente de pago
        </h1>
        <p style="color: #CCCCCC; font-size: 15px; line-height: 1.6;">
          Hola <strong>${nombre}</strong>, intentamos procesar la renovación de tu membresía por <strong>$${monto || '499'} MXN</strong>, pero tu entidad bancaria rechazó el cargo o la tarjeta expiró.
        </p>
        <p style="color: #CCCCCC; font-size: 15px; line-height: 1.6;">
          Para evitar que se bloquee tu acceso al torniquete biométrico y no pierdas tu progreso en la app, actualiza tus datos con un solo toque:
        </p>
        <div style="text-align: center; margin: 32px 0;">
          <a href="${deepLink}"
             style="background: #FF007A; color: #FFFFFF; padding: 16px 32px; border-radius: 30px; text-decoration: none; font-weight: bold; font-size: 15px; display: inline-block; box-shadow: 0 8px 24px rgba(255, 0, 122, 0.4);">
            💳 Actualizar Tarjeta en 1 Clic
          </a>
        </div>
        <p style="color: #888888; font-size: 13px; text-align: center;">
          Si ya realizaste el pago en recepción o en efectivo, por favor ignora este mensaje.
        </p>
      </div>
    `,
  });
}

module.exports = {
  send,
  sendReactivationEmail,
  sendPaymentRecoveryEmail,
};
