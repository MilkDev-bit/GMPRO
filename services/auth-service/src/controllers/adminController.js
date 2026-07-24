/**
 * @file services/auth-service/src/controllers/adminController.js
 * @description Endpoints de administración de miembros (panel staff/admin).
 * Protegidos por RBAC (requiredRoles) + blacklist en las rutas.
 */

'use strict';

const userModel = require('../models/userModel');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:adminController');

// GET /api/v1/auth/admin/members?search=
async function listMembers(req, res, next) {
  try {
    const members = await userModel.listMembers({ search: req.query.search || '' });
    return res.status(200).json({ success: true, data: members, error: null });
  } catch (err) {
    next(err);
  }
}

// PATCH /api/v1/auth/admin/members/:id  { activo: boolean }
async function setMemberActive(req, res, next) {
  try {
    const { id } = req.params;
    const { activo } = req.body;
    const updated = await userModel.setActive(id, activo);
    if (!updated) {
      return res.status(404).json({ success: false, data: null, error: 'Miembro no encontrado.' });
    }
    logger.info('Estado de miembro cambiado por admin', {
      adminId: req.user.id, targetId: id, activo,
    });
    return res.status(200).json({ success: true, data: updated, error: null });
  } catch (err) {
    next(err);
  }
}

module.exports = { listMembers, setMemberActive };
