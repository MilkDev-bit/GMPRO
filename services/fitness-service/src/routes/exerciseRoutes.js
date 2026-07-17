/**
 * @file services/fitness-service/src/routes/exerciseRoutes.js
 * @description Rutas para consulta de ejercicios del catálogo.
 */

'use strict';

const { Router }                 = require('express');
const exerciseController         = require('../controllers/exerciseController');

const router = Router();

// GET /api/v1/exercises -> Lista y filtra el catálogo de ejercicios
router.get('/', exerciseController.listExercises);

// GET /api/v1/exercises/:id -> Obtiene detalle del ejercicio
router.get('/:id', exerciseController.getExerciseDetail);

module.exports = router;
