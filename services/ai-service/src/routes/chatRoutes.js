/**
 * @file services/ai-service/src/routes/chatRoutes.js
 * @description Rutas para el asistente conversacional con streaming SSE.
 */

'use strict';

const { Router }                 = require('express');
const { body, validationResult } = require('express-validator');
const chatController             = require('../controllers/chatController');

const router = Router();

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false, data: null,
      error: errors.array().map((e) => `${e.path}: ${e.msg}`).join(' | '),
    });
  }
  next();
}

// POST /api/v1/chat/stream -> Inicia stream conversacional SSE con GymBot
router.post(
  '/stream',
  [
    body('message').notEmpty().isString().withMessage('El mensaje (message) es requerido.'),
    body('history').optional().isArray().withMessage('El historial debe ser un arreglo de mensajes previos.'),
  ],
  validate,
  chatController.streamChat
);

module.exports = router;
