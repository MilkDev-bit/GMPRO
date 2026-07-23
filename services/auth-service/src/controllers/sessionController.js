/**
 * @file services/auth-service/src/controllers/sessionController.js
 * @description Gestión de dispositivos/sesiones activas del usuario, sobre el
 * modelo de familias de refresh tokens.
 *
 *   GET    /api/v1/auth/sessions             → lista las sesiones activas
 *   DELETE /api/v1/auth/sessions/:familyId   → cierra un dispositivo concreto
 *   DELETE /api/v1/auth/sessions             → cierra TODAS las sesiones
 *
 * Todas requieren JWT (req.user.id). La revocación por familyId está protegida
 * contra BOLA/IDOR: el modelo filtra por user_id, así que un usuario nunca puede
 * cerrar la sesión de otro aunque adivine su familyId.
 */

'use strict';

const refreshTokenModel = require('../models/refreshTokenModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:sessionController');

// ── GET /api/v1/auth/sessions ────────────────────────────────────────────────
async function listSessions(req, res, next) {
  try {
    const sessions = await refreshTokenModel.listActiveSessionsForUser(req.user.id);
    return res.status(200).json({
      success: true,
      data: { total: sessions.length, sessions },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── DELETE /api/v1/auth/sessions/:familyId ───────────────────────────────────
async function revokeSession(req, res, next) {
  try {
    const { familyId } = req.params;
    const revoked = await refreshTokenModel.revokeFamilyForUser(req.user.id, familyId);

    // 0 filas → o no existe o no pertenece al usuario. Se responde 404 sin
    // distinguir ambos casos (no filtra existencia de sesiones ajenas).
    if (revoked === 0) {
      return res.status(404).json({
        success: false, data: null,
        error: 'Sesión no encontrada.',
      });
    }

    logger.info('Sesión (dispositivo) revocada por el usuario', {
      userId: req.user.id, familyId, revoked,
    });
    return res.status(200).json({
      success: true,
      data: { familyId, revoked },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

// ── DELETE /api/v1/auth/sessions  (cerrar TODAS) ─────────────────────────────
async function revokeAllSessions(req, res, next) {
  try {
    const revoked = await refreshTokenModel.revokeAllForUser(req.user.id);
    // Limpia también la cookie del dispositivo actual.
    res.clearCookie('refreshToken', { path: '/api/v1/auth/refresh' });

    logger.info('Todas las sesiones revocadas por el usuario', { userId: req.user.id, revoked });
    return res.status(200).json({
      success: true,
      data: { revoked, mensaje: 'Se cerraron todas las sesiones. Vuelve a iniciar sesión.' },
      error: null,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  listSessions,
  revokeSession,
  revokeAllSessions,
};
