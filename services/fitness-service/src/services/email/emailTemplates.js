/**
 * @file services/fitness-service/src/services/email/emailTemplates.js
 * @description Plantillas HTML transaccionales con la estética "Neon Sport Dark".
 *
 * DECISIONES DE COMPATIBILIDAD (clientes de correo, no navegadores):
 *   • Layout con <table> (Outlook/Gmail ignoran flexbox y grid).
 *   • CSS 100% INLINE (Gmail elimina <style> en muchos casos).
 *   • Ancho máximo 600px + escalado fluido → responsivo en móvil.
 *   • Sin degradados CSS críticos: los fondos neón se resuelven con colores planos
 *     y bordes, porque `linear-gradient` no se renderiza en Outlook.
 *
 * SEGURIDAD: toda variable inyectada pasa por escapeHtml() para impedir que un
 * nombre de usuario o de rutina con etiquetas inyecte markup en el correo.
 */

'use strict';

// ── Tokens de marca (espejo de app_colors.dart) ─────────────────────────────
const BRAND = Object.freeze({
  bg:        '#080614', // Fondo obsidiana
  surface:   '#18152D', // Tarjeta
  surfaceAlt:'#1E1B38',
  border:    '#2A2545',
  textHi:    '#FFFFFF',
  textMid:   '#B0A8D4',
  textLow:   '#68608C',
  cyan:      '#00F0FF',
  pink:      '#FF007A',
  purple:    '#B24DFF', // variante texto-segura
  emerald:   '#00E676',
});

/**
 * Escapa caracteres peligrosos para HTML.
 * @param {*} value
 * @returns {string}
 */
function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Sustituye {{variables}} de una plantilla escapando cada valor.
 * Las claves ausentes se reemplazan por cadena vacía (nunca deja "{{x}}" visible).
 *
 * @param {string} template
 * @param {Record<string, any>} vars
 * @returns {string}
 */
function renderTemplate(template, vars = {}) {
  return template.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, key) => {
    return escapeHtml(vars[key]);
  });
}

/**
 * Envoltorio base: cabecera de marca, tarjeta de contenido y pie legal.
 * @param {object} params
 * @param {string} params.preheader - Texto de vista previa en la bandeja.
 * @param {string} params.accent    - Color de acento (hex).
 * @param {string} params.bodyHtml  - Contenido ya renderizado.
 */
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
<!-- Preheader oculto: primera línea que muestra la bandeja de entrada -->
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader)}</div>

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:${BRAND.bg};padding:24px 12px;">
  <tr>
    <td align="center">

      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">

        <!-- CABECERA -->
        <tr>
          <td align="center" style="padding:8px 0 24px 0;">
            <span style="font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:22px;font-weight:800;letter-spacing:3px;color:${BRAND.textHi};">
              GYM<span style="color:${accent};">PRO</span>
            </span>
          </td>
        </tr>

        <!-- TARJETA DE CONTENIDO -->
        <tr>
          <td style="background-color:${BRAND.surface};border:1px solid ${BRAND.border};border-radius:20px;padding:32px 28px;">
            ${bodyHtml}
          </td>
        </tr>

        <!-- PIE -->
        <tr>
          <td align="center" style="padding:24px 12px 8px 12px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:18px;color:${BRAND.textLow};">
            Recibes este correo porque tienes una cuenta activa en GymPro.<br>
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

/** Botón CTA compatible con Outlook (tabla, no <button>). */
function ctaButton(label, url, accent) {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:28px 0 4px 0;">
  <tr>
    <td align="center" bgcolor="${accent}" style="border-radius:28px;">
      <a href="${escapeHtml(url)}" target="_blank"
         style="display:inline-block;padding:14px 32px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:#0A0714;text-decoration:none;border-radius:28px;">
        ${escapeHtml(label)}
      </a>
    </td>
  </tr>
</table>`;
}

/** Fila de estadística (etiqueta + valor) para el resumen de entrenamiento. */
function statRow(label, value, accent) {
  return `<tr>
  <td style="padding:10px 0;border-bottom:1px solid ${BRAND.border};font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:13px;color:${BRAND.textMid};">
    ${escapeHtml(label)}
  </td>
  <td align="right" style="padding:10px 0;border-bottom:1px solid ${BRAND.border};font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:${accent};">
    ${escapeHtml(value)}
  </td>
</tr>`;
}

// ── PLANTILLAS DISPONIBLES ──────────────────────────────────────────────────
// Cada plantilla recibe `vars` y devuelve { subject, html }.

const TEMPLATES = {
  /**
   * Rutina completada. vars: { nombre, rutina, duracionMin, ejercicios, seriesTotal, appUrl }
   */
  workout_completed: (vars) => {
    const accent = BRAND.emerald;
    const body = `
      <p style="margin:0 0 6px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">
        ENTRENAMIENTO COMPLETADO
      </p>
      <h1 style="margin:0 0 16px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">
        ¡Felicidades {{nombre}}, has completado {{rutina}}!
      </h1>
      <p style="margin:0 0 20px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:24px;color:${BRAND.textMid};">
        Otra sesión menos para tu objetivo. Aquí tienes el resumen de hoy:
      </p>

      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
        ${statRow('Duración', '{{duracionMin}} min', accent)}
        ${statRow('Ejercicios', '{{ejercicios}}', accent)}
        ${statRow('Series totales', '{{seriesTotal}}', accent)}
      </table>

      ${ctaButton('Ver mi progreso', '{{appUrl}}', accent)}
    `;
    return {
      subject: `¡Completaste {{rutina}}, {{nombre}}! 💪`,
      html: baseLayout({
        preheader: 'Resumen de tu entrenamiento de hoy en GymPro',
        accent,
        bodyHtml: body,
      }),
    };
  },

  /**
   * Recordatorio de entrenamiento. vars: { nombre, rutina, appUrl }
   */
  workout_reminder: (vars) => {
    const accent = BRAND.cyan;
    const body = `
      <p style="margin:0 0 6px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">
        TE ESPERA EL GIMNASIO
      </p>
      <h1 style="margin:0 0 16px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">
        {{nombre}}, hoy toca {{rutina}}
      </h1>
      <p style="margin:0 0 8px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:24px;color:${BRAND.textMid};">
        Tu plan de IA ya tiene la sesión lista. Constancia &gt; intensidad.
      </p>
      ${ctaButton('Empezar entrenamiento', '{{appUrl}}', accent)}
    `;
    return {
      subject: `{{nombre}}, hoy toca {{rutina}} 🔥`,
      html: baseLayout({
        preheader: 'Tu sesión de hoy te está esperando',
        accent,
        bodyHtml: body,
      }),
    };
  },

  /**
   * Hito/logro alcanzado. vars: { nombre, logro, detalle, appUrl }
   */
  milestone_reached: (vars) => {
    const accent = BRAND.pink;
    const body = `
      <p style="margin:0 0 6px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;font-weight:700;letter-spacing:2px;color:${accent};">
        NUEVO LOGRO
      </p>
      <h1 style="margin:0 0 16px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:26px;line-height:32px;font-weight:800;color:${BRAND.textHi};">
        {{nombre}}, desbloqueaste: {{logro}}
      </h1>
      <p style="margin:0 0 8px 0;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:24px;color:${BRAND.textMid};">
        {{detalle}}
      </p>
      ${ctaButton('Ver mis logros', '{{appUrl}}', accent)}
    `;
    return {
      subject: `🏆 {{nombre}}, desbloqueaste {{logro}}`,
      html: baseLayout({
        preheader: 'Has alcanzado un nuevo hito en GymPro',
        accent,
        bodyHtml: body,
      }),
    };
  },
};

/**
 * Renderiza una plantilla por nombre con sus variables.
 *
 * @param {keyof TEMPLATES} templateName
 * @param {Record<string, any>} vars
 * @returns {{ subject: string, html: string }}
 * @throws {Error} si la plantilla no existe
 */
function render(templateName, vars = {}) {
  const factory = TEMPLATES[templateName];
  if (!factory) {
    throw new Error(`Plantilla de email desconocida: "${templateName}"`);
  }
  const { subject, html } = factory(vars);
  return {
    subject: renderTemplate(subject, vars),
    html:    renderTemplate(html, vars),
  };
}

module.exports = {
  render,
  renderTemplate,
  escapeHtml,
  TEMPLATE_NAMES: Object.keys(TEMPLATES),
  BRAND,
};
