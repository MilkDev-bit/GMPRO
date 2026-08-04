/**
 * @file services/auth-service/src/services/emailService.js
 * @description Envío de emails transaccionales vía Resend.com
 *
 * Resend es el proveedor recomendado por su SDK simple y alta entregabilidad.
 * Si RESEND_API_KEY no está configurado, los emails se loguean en consola
 * (útil en desarrollo local sin configurar proveedor real).
 */

"use strict";

const env = require("../config/environment");
const {
  createServiceLogger,
} = require("../../../../packages_shared/security/logger");

const logger = createServiceLogger("auth-service:emailService");

// ── Diseño "Neon Sport Dark" (mismo lenguaje visual que fitness-service) ───
// Solo maquetación/estilos: ningún cambio de comportamiento de envío.
const BRAND = Object.freeze({
  bg: "#080614",
  surface: "#18152D",
  border: "#2A2545",
  textHi: "#FFFFFF",
  textMid: "#B0A8D4",
  textLow: "#68608C",
  cyan: "#00F0FF",
  purple: "#B24DFF",
  pink: "#FF007A",
});
const FONT = "'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

/** Escapa valores dinámicos (p. ej. el nombre del usuario) antes de inyectarlos en HTML. */
function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Botón CTA compatible con Outlook (tabla, no <button>). */
function ctaButton(label, url, accent) {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:28px auto 4px auto;">
  <tr>
    <td align="center" bgcolor="${accent}" style="border-radius:28px;">
      <a href="${escapeHtml(url)}" target="_blank"
         style="display:inline-block;padding:14px 32px;font-family:${FONT};font-size:15px;font-weight:700;color:#0A0714;text-decoration:none;border-radius:28px;">
        ${escapeHtml(label)}
      </a>
    </td>
  </tr>
</table>`;
}

/** Envoltorio base: cabecera de marca, tarjeta de contenido y pie legal. */
function baseLayout({ preheader, accent, bodyHtml }) {
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>GymPro</title>
</head>
<body style="margin:0;padding:0;background-color:${BRAND.bg};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:${BRAND.bg};padding:24px 12px;">
  <tr>
    <td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">
        <tr>
          <td align="center" style="padding:8px 0 24px 0;">
            <span style="font-family:${FONT};font-size:22px;font-weight:800;letter-spacing:3px;color:${BRAND.textHi};">
              GYM<span style="color:${accent};">PRO</span>
            </span>
          </td>
        </tr>
        <tr>
          <td style="background-color:${BRAND.surface};border:1px solid ${BRAND.border};border-radius:20px;padding:32px 28px;">
            ${bodyHtml}
          </td>
        </tr>
        <tr>
          <td align="center" style="padding:24px 12px 8px 12px;font-family:${FONT};font-size:12px;line-height:18px;color:${BRAND.textLow};">
            Recibes este correo porque tienes una cuenta en GymPro.<br>
            © 2026 GymPro Technologies Inc.
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
}

// Inicializar SDK de Resend si la clave está disponible
let resendClient = null;
if (env.RESEND_API_KEY) {
  const { Resend } = require("resend");
  resendClient = new Resend(env.RESEND_API_KEY);
  logger.info("Resend email client inicializado");
} else {
  logger.warn(
    "RESEND_API_KEY no configurado. Los emails se simularán en consola.",
  );
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
    logger.info("[EMAIL SIMULADO]", {
      to,
      subject,
      preview: html.substring(0, 100),
    });
    return;
  }

  try {
    const { error } = await resendClient.emails.send({
      from: `${env.EMAIL_FROM_NAME} <${env.EMAIL_FROM}>`,
      to: [to],
      subject,
      html,
    });

    if (error) throw new Error(error.message);
    logger.info("Email enviado exitosamente", { to, subject });
  } catch (err) {
    // No lanzar error al caller: el fallo de email no debe impedir el flujo principal
    // (ej: el registro se completa aunque falle el email de verificación)
    logger.error("Fallo al enviar email", { to, subject, error: err.message });
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
async function sendVerificationEmail({
  email,
  nombre,
  verificationToken,
  appDeepLink,
}) {
  const verifyUrl = `${appDeepLink || "https://app.tugimnasio.com"}/verify-email?token=${verificationToken}`;

  const accent = BRAND.purple;
  await send({
    to: email,
    subject: "¡Bienvenido a GymPro! Verifica tu cuenta",
    html: baseLayout({
      preheader: "Confirma tu cuenta para empezar a entrenar",
      accent,
      bodyHtml: `
        <p style="margin:0 0 6px 0;font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">BIENVENIDA</p>
        <h1 style="margin:0 0 16px 0;font-family:${FONT};font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">¡Hola, ${escapeHtml(nombre)}! 💪</h1>
        <p style="margin:0 0 8px 0;font-family:${FONT};font-size:15px;line-height:24px;color:${BRAND.textMid};">
          Gracias por registrarte en <strong style="color:${BRAND.textHi};">GymPro</strong>. Para activar tu cuenta, confirma tu correo:
        </p>
        ${ctaButton("Verificar mi cuenta", verifyUrl, accent)}
        <p style="margin:24px 0 0 0;font-family:${FONT};font-size:13px;line-height:20px;color:${BRAND.textLow};">
          Este enlace expira en <strong style="color:${BRAND.textMid};">24 horas</strong>.<br>
          Si no creaste esta cuenta, ignora este email.
        </p>
      `,
    }),
  });
}

/**
 * Envía el email con el CÓDIGO OTP de verificación (6 dígitos).
 * Reemplaza al flujo de enlace: la app pide un código, no un link.
 *
 * @param {object} params
 * @param {string} params.email
 * @param {string} params.nombre
 * @param {string} params.codigo   - Código de 6 dígitos (texto plano; vive en Redis con TTL)
 * @param {number} [params.ttlMin] - Minutos de validez (para el texto del email)
 */
async function sendVerificationCodeEmail({
  email,
  nombre,
  codigo,
  ttlMin = 10,
}) {
  const accent = BRAND.cyan;
  await send({
    to: email,
    subject: `Tu código de verificación GymPro: ${codigo}`,
    html: baseLayout({
      preheader: `Tu código de verificación es ${codigo}`,
      accent,
      bodyHtml: `
        <p style="margin:0 0 6px 0;font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">TU CÓDIGO DE ACCESO</p>
        <h1 style="margin:0 0 16px 0;font-family:${FONT};font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">¡Hola, ${escapeHtml(nombre)}! 💪</h1>
        <p style="margin:0 0 8px 0;font-family:${FONT};font-size:15px;line-height:24px;color:${BRAND.textMid};">
          Usa este código para verificar tu cuenta en <strong style="color:${BRAND.textHi};">GymPro</strong>:
        </p>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:28px 0;">
          <tr>
            <td align="center">
              <span style="display:inline-block;font-family:${FONT};font-size:36px;font-weight:800;letter-spacing:12px;color:${accent};background-color:${BRAND.bg};border:1px solid ${BRAND.border};border-radius:16px;padding:18px 16px 18px 28px;">${codigo}</span>
            </td>
          </tr>
        </table>
        <p style="margin:0;font-family:${FONT};font-size:13px;line-height:20px;color:${BRAND.textLow};">
          El código expira en <strong style="color:${BRAND.textMid};">${ttlMin} minutos</strong>.<br>
          Si no creaste esta cuenta, ignora este email.
        </p>
      `,
    }),
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

  const accent = BRAND.pink;
  await send({
    to: email,
    subject: "Restablecimiento de contraseña — GymPro",
    html: baseLayout({
      preheader: "Solicitaste restablecer tu contraseña de GymPro",
      accent,
      bodyHtml: `
        <p style="margin:0 0 6px 0;font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">RESTABLECER CONTRASEÑA</p>
        <h1 style="margin:0 0 16px 0;font-family:${FONT};font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">Hola, ${escapeHtml(nombre)}</h1>
        <p style="margin:0 0 8px 0;font-family:${FONT};font-size:15px;line-height:24px;color:${BRAND.textMid};">
          Recibimos una solicitud para restablecer tu contraseña.
        </p>
        ${ctaButton("Restablecer contraseña", resetUrl, accent)}
        <p style="margin:24px 0 0 0;font-family:${FONT};font-size:13px;line-height:20px;color:${BRAND.textLow};">
          Si el botón no funciona, copia este enlace en tu navegador:<br>
          <a href="${escapeHtml(webFallback)}" style="color:${accent};word-break:break-all;">${escapeHtml(webFallback)}</a>
        </p>
        <p style="margin:16px 0 0 0;font-family:${FONT};font-size:13px;line-height:20px;color:#FF6B6B;">
          ⚠️ Este enlace expira en <strong>1 hora</strong>.
          Si no solicitaste este cambio, ignora este email — tu contraseña no cambiará.
        </p>
      `,
    }),
  });
}

module.exports = {
  sendVerificationEmail,
  sendVerificationCodeEmail,
  sendPasswordResetEmail,
};
