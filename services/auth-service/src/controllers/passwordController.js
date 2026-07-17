/**
 * @file services/auth-service/src/controllers/passwordController.js
 * @description Controladores de recuperación y cambio de contraseña.
 */

'use strict';

const bcrypt          = require('bcrypt');
const userModel       = require('../models/userModel');
const resetTokenModel = require('../models/resetTokenModel');
const tokenService    = require('../services/tokenService');
const emailService    = require('../services/emailService');
const env             = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:passwordController');

// ── POST /api/v1/auth/forgot-password ─────────────────────────────────────────
/**
 * Genera y envía un token de reset de contraseña.
 *
 * SEGURIDAD: Siempre retorna 200 aunque el email no exista
 * para no revelar si un email está registrado (OWASP A07).
 */
async function forgotPassword(req, res, next) {
  try {
    const { email } = req.body;

    const GENERIC_RESPONSE = {
      success: true,
      data: { mensaje: 'Si el email existe, recibirás un enlace para restablecer tu contraseña.' },
      error: null,
    };

    const user = await userModel.findByEmailForAuth(email);

    // Respuesta genérica si el usuario no existe (no revelar si el email está registrado)
    if (!user || !user.activo) {
      return res.status(200).json(GENERIC_RESPONSE);
    }

    // Generar token y guardarlo en DB (hash)
    const { token, hash } = tokenService.generatePasswordResetToken();
    await resetTokenModel.create(user.id, hash);

    // Enviar email con el token en texto plano
    await emailService.sendPasswordResetEmail({
      email:      user.email,
      nombre:     user.nombre,
      resetToken: token,
    });

    logger.info('Solicitud de reset de contraseña procesada', { userId: user.id });
    return res.status(200).json(GENERIC_RESPONSE);

  } catch (err) {
    next(err);
  }
}

// ── POST /api/v1/auth/reset-password ──────────────────────────────────────────
/**
 * Restablece la contraseña usando el token del email.
 */
async function resetPassword(req, res, next) {
  try {
    const { token, newPassword } = req.body;

    // Buscar el token por su hash
    const tokenHash  = tokenService.hashResetToken(token);
    const tokenRecord = await resetTokenModel.findValidToken(tokenHash);

    if (!tokenRecord) {
      return res.status(400).json({
        success: false, data: null,
        error: 'El enlace de restablecimiento es inválido o ha expirado.',
      });
    }

    // Hashear nueva contraseña
    const newHash = await bcrypt.hash(newPassword, env.BCRYPT_ROUNDS);

    // Actualizar contraseña e invalidar todas las sesiones
    await userModel.updatePassword(tokenRecord.usuario_id, newHash);

    // Marcar token como usado (no puede usarse de nuevo)
    await resetTokenModel.markAsUsed(tokenRecord.id);

    logger.info('Contraseña restablecida', { userId: tokenRecord.usuario_id });

    return res.status(200).json({
      success: true,
      data: { mensaje: 'Contraseña restablecida exitosamente. Por favor inicia sesión.' },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

// ── PUT /api/v1/auth/change-password ──────────────────────────────────────────
/**
 * Cambia la contraseña de un usuario autenticado (conoce la contraseña actual).
 * Requiere JWT válido.
 */
async function changePassword(req, res, next) {
  try {
    const { currentPassword, newPassword } = req.body;
    const userId = req.user.id;

    // Obtener usuario con hash actual
    const user = await userModel.findByEmailForAuth(req.user.email);
    if (!user) {
      return res.status(404).json({ success: false, data: null, error: 'Usuario no encontrado.' });
    }

    // Verificar contraseña actual
    const isCorrect = await bcrypt.compare(currentPassword, user.password_hash);
    if (!isCorrect) {
      return res.status(401).json({
        success: false, data: null,
        error: 'La contraseña actual es incorrecta.',
      });
    }

    // Verificar que la nueva contraseña sea diferente
    const isSamePassword = await bcrypt.compare(newPassword, user.password_hash);
    if (isSamePassword) {
      return res.status(400).json({
        success: false, data: null,
        error: 'La nueva contraseña debe ser diferente a la actual.',
      });
    }

    const newHash = await bcrypt.hash(newPassword, env.BCRYPT_ROUNDS);
    await userModel.updatePassword(userId, newHash);

    logger.info('Contraseña cambiada por el usuario', { userId });

    return res.status(200).json({
      success: true,
      data: { mensaje: 'Contraseña actualizada. Todas las sesiones han sido cerradas.' },
      error: null,
    });

  } catch (err) {
    next(err);
  }
}

module.exports = { forgotPassword, resetPassword, changePassword };
