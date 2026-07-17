/**
 * @file services/fitness-service/src/routes/internalRoutes.js
 * @description Rutas internas M2M para compartir contexto de usuario con ai-service.
 */

'use strict';

const { Router }         = require('express');
const internalController = require('../controllers/internalController');

const router = Router();

// GET /api/v1/internal/user-context?userId=UUID -> Resumen de progreso y rutinas
router.get('/', internalController.getUserContext);

module.exports = router;
