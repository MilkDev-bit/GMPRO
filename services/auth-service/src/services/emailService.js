/**
 * @file services/auth-service/src/services/emailService.js
 * @description Envío de emails transaccionales vía Resend.com
 *
 * Resend es el proveedor recomendado por su SDK simple y alta entregabilidad.
 * Si RESEND_API_KEY no está configurado, los emails se loguean en consola
 * (útil en desarrollo local sin configurar proveedor real).
 */

'use strict';

const env = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:emailService');

// Inicializar SDK de Resend si la clave está disponible
let resendClient = null;
if (env.RESEND_API_KEY) {
  const { Resend } = require('resend');
  resendClient = new Resend(env.RESEND_API_KEY);
  logger.info('Resend email client inicializado');
} else {
  logger.warn('RESEND_API_KEY no configurado. Los emails se simularán en consola.');
}

/**
 * Función base de envío. Si Resend no está disponible, loguea el email.
 *
 * @param {object} options
 * @param {string} options.to
 * @param {string} options.subject
 * @param {string} options.html
 * @returns {Promise<void>}
 */
async function send({ to, subject, html }) {
  if (!resendClient) {
    // Modo desarrollo: simular envío
    logger.info('[EMAIL SIMULADO]', { to, subject, preview: html.substring(0, 100) });
    return;
  }

  try {
    const { error } = await resendClient.emails.send({
      from:    `${env.EMAIL_FROM_NAME} <${env.EMAIL_FROM}>`,
      to:      [to],
      subject,
      html,
    });

    if (error) throw new Error(error.message);
    logger.info('Email enviado exitosamente', { to, subject });

  } catch (err) {
    // No lanzar error al caller: el fallo de email no debe impedir el flujo principal
    // (ej: el registro se completa aunque falle el email de verificación)
    logger.error('Fallo al enviar email', { to, subject, error: err.message });
  }
}

/**
 * Envía el email de verificación de cuenta.
 *
 * @param {object} params
 * @param {string} params.email
 * @param {string} params.nombre
 * @param {string} params.verificationToken - UUID almacenado en DB
 * @param {string} params.appDeepLink       - URL o deep link de la app móvil
 */
async function sendVerificationEmail({ email, nombre, verificationToken, appDeepLink }) {
  const verifyUrl = `${appDeepLink || 'https://app.tugimnasio.com'}/verify-email?token=${verificationToken}`;

  await send({
    to:      email,
    subject: '¡Bienvenido a GymPro! Verifica tu cuenta',
    html: `
      <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h1 style="color: #1a1a2e;">¡Hola, ${nombre}! 💪</h1>
        <p>Gracias por registrarte en <strong>GymPro</strong>. Para activar tu cuenta, haz clic en el botón:</p>
        <div style="text-align: center; margin: 30px 0;">
          <a href="${verifyUrl}"
             style="background: #4f46e5; color: white; padding: 14px 28px;
                    border-radius: 8px; text-decoration: none; font-weight: bold;">
            Verificar mi cuenta
          </a>
        </div>
        <p style="color: #666; font-size: 14px;">
          Este enlace expira en <strong>24 horas</strong>.<br>
          Si no creaste esta cuenta, ignora este email.
        </p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
        <p style="color: #999; font-size: 12px;">GymPro · Tu gimnasio inteligente</p>
      </div>
    `,
  });
}

/**
 * Envía el email de restablecimiento de contraseña.
 *
 * @param {object} params
 * @param {string} params.email
 * @param {string} params.nombre
 * @param {string} params.resetToken - Token en texto plano (NO el hash)
 */
async function sendPasswordResetEmail({ email, nombre, resetToken }) {
  // El deep link abre la app directamente en la pantalla de nueva contraseña
  const resetUrl = `gympro://reset-password?token=${resetToken}`;
  const webFallback = `https://app.tugimnasio.com/reset-password?token=${resetToken}`;

  await send({
    to:      email,
    subject: 'Restablecimiento de contraseña — GymPro',
    html: `
      <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h1 style="color: #1a1a2e;">Restablecer contraseña</h1>
        <p>Hola <strong>${nombre}</strong>, recibimos una solicitud para restablecer tu contraseña.</p>
        <div style="text-align: center; margin: 30px 0;">
          <a href="${resetUrl}"
             style="background: #4f46e5; color: white; padding: 14px 28px;
                    border-radius: 8px; text-decoration: none; font-weight: bold;">
            Restablecer contraseña
          </a>
        </div>
        <p style="color: #666; font-size: 14px;">
          Si el botón no funciona, copia este enlace en tu navegador:<br>
          <a href="${webFallback}" style="color: #4f46e5; word-break: break-all;">${webFallback}</a>
        </p>
        <p style="color: #e74c3c; font-size: 14px;">
          ⚠️ Este enlace expira en <strong>1 hora</strong>.
          Si no solicitaste este cambio, ignora este email — tu contraseña no cambiará.
        </p>
      </div>
    `,
  });
}

module.exports = { sendVerificationEmail, sendPasswordResetEmail };
