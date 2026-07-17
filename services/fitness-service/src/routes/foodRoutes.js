/**
 * @file services/fitness-service/src/routes/foodRoutes.js
 * @description Rutas para búsqueda y consulta de alimentos Open Food Facts.
 */

'use strict';

const { Router }       = require('express');
const foodController   = require('../controllers/foodController');

const router = Router();

// GET /api/v1/foods/search?q=...
router.get('/search', foodController.searchFoods);

// GET /api/v1/foods/barcode/:code
router.get('/barcode/:code', foodController.getFoodByBarcode);

module.exports = router;
