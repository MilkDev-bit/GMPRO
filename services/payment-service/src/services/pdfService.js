/**
 * @file services/payment-service/src/services/pdfService.js
 * @description Servicio para generación de recibos en PDF de calidad profesional.
 *
 * Utiliza PDFKit para generar comprobantes oficiales de pago (en efectivo o tarjeta)
 * con diseño moderno, folios únicos, desglose fiscal y firma digitalizada.
 */

'use strict';

const PDFDocument = require('pdfkit');
const env = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:pdfService');

/**
 * Genera un buffer de PDF para un recibo de pago de GymPro.
 *
 * @param {object} params
 * @param {object} params.subscription - Datos de la suscripción/pago
 * @param {object} params.user         - Datos básicos del usuario (nombre, email)
 * @param {string} [params.receptionistId] - ID del recepcionista si fue pago en efectivo
 * @returns {Promise<Buffer>}
 */
function generateReceiptPdf({ subscription, user, receptionistId = null }) {
  return new Promise((resolve, reject) => {
    try {
      // ── Blindaje de entrada: coerción segura para no romper la generación ────
      // Evita que un registro con campos nulos o caracteres de control (emoji,
      // \x00, etc.) lance una excepción y devuelva 500 en el endpoint de recibo.
      subscription = subscription || {};
      user = user || {};
      const clean = (v, max = 80) =>
        String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').slice(0, max);
      const safeId      = clean(subscription.id || 'SIN-FOLIO', 40);
      const safeEstado  = clean(subscription.estado || 'active', 20);
      const safeUserId  = clean(subscription.usuario_id || '', 40);

      const doc = new PDFDocument({
        size: 'LETTER',
        margins: { top: 50, bottom: 50, left: 50, right: 50 },
        info: {
          Title: `Recibo de Pago - ${subscription.id}`,
          Author: env.BUSINESS_NAME || 'GymPro',
          Subject: `Comprobante de Suscripción - ${subscription.plan_nombre}`,
        },
      });

      const buffers = [];
      doc.on('data', (chunk) => buffers.push(chunk));
      doc.on('end', () => {
        const pdfData = Buffer.concat(buffers);
        logger.info('PDF generado exitosamente', {
          subscriptionId: subscription.id,
          sizeBytes: pdfData.length,
        });
        resolve(pdfData);
      });
      doc.on('error', (err) => reject(err));

      // ── COLORES Y ESTILOS ──────────────────────────────────────────────────
      const primaryColor = '#4f46e5';   // Indigo GymPro
      const darkColor    = '#1e293b';   // Slate 800
      const lightColor   = '#f8fafc';   // Slate 50
      const grayColor    = '#64748b';   // Slate 500
      const accentColor  = '#10b981';   // Emerald 500 (Pagado)

      // ── ENCABEZADO / HEADER ────────────────────────────────────────────────
      doc.rect(0, 0, doc.page.width, 110).fill(primaryColor);
      
      doc.fillColor('#ffffff')
         .fontSize(26)
         .font('Helvetica-Bold')
         .text('GYMPRO', 50, 40);

      doc.fontSize(11)
         .font('Helvetica')
         .text('TU GIMNASIO INTELIGENTE', 50, 70);

      doc.fontSize(20)
         .font('Helvetica-Bold')
         .text('COMPROBANTE DE PAGO', 0, 45, { align: 'right' });

      doc.fontSize(10)
         .font('Helvetica')
         .text(`Folio: #${safeId.substring(0, 8).toUpperCase()}`, 0, 72, { align: 'right' });

      doc.moveDown(4);

      // ── METADATA DEL CLIENTE Y FECHAS ─────────────────────────────────────
      const startY = 140;
      
      // Caja Izquierda: Datos del Cliente
      doc.rect(50, startY, 240, 95).fillAndStroke(lightColor, '#e2e8f0');
      doc.fillColor(darkColor).fontSize(11).font('Helvetica-Bold').text('RECIBÍ DE:', 65, startY + 15);
      doc.font('Helvetica').fontSize(10).fillColor(darkColor);
      doc.text(user.nombre ? `${clean(user.nombre, 60)} ${clean(user.apellido_paterno, 60)}`.trim() : `Usuario ID: ${safeUserId}`, 65, startY + 35);
      doc.text(clean(user.email, 80) || 'Email no disponible', 65, startY + 52);
      doc.text(`ID Cliente: ${safeUserId.substring(0, 8)}`, 65, startY + 69);

      // Caja Derecha: Datos del Comprobante
      doc.rect(310, startY, 250, 95).fillAndStroke(lightColor, '#e2e8f0');
      doc.fillColor(darkColor).fontSize(11).font('Helvetica-Bold').text('DETALLES DEL COBRO:', 325, startY + 15);
      doc.font('Helvetica').fontSize(10).fillColor(darkColor);
      doc.text(`Fecha de Pago: ${new Date(subscription.ultimo_pago_en || subscription.valido_desde || Date.now()).toLocaleDateString('es-MX')}`, 325, startY + 35);
      doc.text(`Método: ${subscription.metodo_pago === 'cash' ? 'EFECTIVO (Caja)' : 'TARJETA / STRIPE'}`, 325, startY + 52);
      if (receptionistId) {
        doc.text(`Atendió: ${receptionistId}`, 325, startY + 69);
      } else {
        doc.text(`Estado: PAGADO (${safeEstado.toUpperCase()})`, 325, startY + 69);
      }

      // ── TABLA DE CONCEPTOS ────────────────────────────────────────────────
      const tableTop = 270;
      doc.rect(50, tableTop, 510, 30).fill(darkColor);
      doc.fillColor('#ffffff').font('Helvetica-Bold').fontSize(10);
      doc.text('CONCEPTO / PLAN DE SUSCRIPCIÓN', 65, tableTop + 10);
      doc.text('PERÍODO DE VIGENCIA', 320, tableTop + 10);
      doc.text('IMPORTE', 480, tableTop + 10);

      const rowTop = tableTop + 30;
      doc.rect(50, rowTop, 510, 45).fillAndStroke('#ffffff', '#e2e8f0');
      doc.fillColor(darkColor).font('Helvetica-Bold').fontSize(11);
      doc.text(subscription.plan_nombre || 'Membresía GymPro', 65, rowTop + 15);
      
      const desde = new Date(subscription.valido_desde || Date.now()).toLocaleDateString('es-MX');
      const hasta = new Date(subscription.valido_hasta || Date.now()).toLocaleDateString('es-MX');
      doc.font('Helvetica').fontSize(10).fillColor(grayColor);
      doc.text(`${desde} al ${hasta} (${subscription.plan_duracion_dias || 30} días)`, 320, rowTop + 16);

      const monto = Number(subscription.monto || 0).toFixed(2);
      const moneda = subscription.moneda || 'MXN';
      doc.font('Helvetica-Bold').fontSize(11).fillColor(darkColor);
      doc.text(`$${monto} ${moneda}`, 480, rowTop + 15);

      // ── TOTAL Y DESGLOSE ──────────────────────────────────────────────────
      const totalTop = rowTop + 65;
      doc.rect(340, totalTop, 220, 80).fillAndStroke(lightColor, '#cbd5e1');
      
      doc.font('Helvetica').fontSize(10).fillColor(grayColor);
      doc.text('Subtotal:', 355, totalTop + 15);
      const subtotal = (monto / 1.16).toFixed(2);
      const iva = (monto - subtotal).toFixed(2);
      doc.text(`$${subtotal} ${moneda}`, 470, totalTop + 15);

      doc.text('IVA (16% int.):', 355, totalTop + 32);
      doc.text(`$${iva} ${moneda}`, 470, totalTop + 32);

      doc.moveTo(355, totalTop + 50).lineTo(545, totalTop + 50).strokeColor('#94a3b8').stroke();

      doc.font('Helvetica-Bold').fontSize(12).fillColor(primaryColor);
      doc.text('TOTAL:', 355, totalTop + 58);
      doc.text(`$${monto} ${moneda}`, 465, totalTop + 58);

      // ── SELLO DE PAGADO Y NOTAS ───────────────────────────────────────────
      doc.save();
      doc.rotate(-12, { origin: [130, totalTop + 30] });
      doc.rect(60, totalTop, 160, 40).strokeColor(accentColor).lineWidth(3).stroke();
      doc.fillColor(accentColor).font('Helvetica-Bold').fontSize(18);
      doc.text('PAGADO / ACTIVE', 68, totalTop + 12);
      doc.restore();

      // ── FOOTER ────────────────────────────────────────────────────────────
      const footerY = doc.page.height - 90;
      doc.moveTo(50, footerY).lineTo(560, footerY).strokeColor('#cbd5e1').lineWidth(1).stroke();

      doc.fontSize(9).font('Helvetica').fillColor(grayColor);
      doc.text('Este documento es un comprobante oficial de pago emitido por GymPro.', 50, footerY + 15, { align: 'center' });
      doc.text('El acceso al establecimiento está sujeto al reglamento interno y a la vigencia del pase QR.', 50, footerY + 30, { align: 'center' });
      doc.font('Helvetica-Bold').text(`GymPro · ${env.BUSINESS_RFC || 'RFC: GYM240101PR0'} · www.gympro.app`, 50, footerY + 48, { align: 'center' });

      doc.end();
    } catch (err) {
      logger.error('Error fatal generando PDF de recibo', { error: err.message });
      reject(err);
    }
  });
}

module.exports = { generateReceiptPdf };
