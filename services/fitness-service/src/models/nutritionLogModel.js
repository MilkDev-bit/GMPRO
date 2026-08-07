/**
 * @file services/fitness-service/src/models/nutritionLogModel.js
 * @description Capa de datos del diario nutricional REAL del socio:
 *   • registros_nutricion   — alimentos consumidos (por día/comida)
 *   • registros_hidratacion — agua bebida por día (upsert usuario+fecha)
 * Todo se acota a fecha = CURRENT_DATE (zona del servidor) para el seguimiento diario.
 */

'use strict';

const { query } = require('../config/database'); // pg directo (svc_fitness)
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('fitness-service:nutritionLogModel');

const COMIDAS_VALIDAS = new Set(['desayuno', 'almuerzo', 'comida', 'cena', 'snack']);
const normComida = (c) => (COMIDAS_VALIDAS.has(String(c || '').toLowerCase()) ? String(c).toLowerCase() : 'snack');

/** Totales del día (calorías + macros consumidas) y agua bebida. */
async function getTodaySummary(usuarioId) {
  const foods = await query(
    `SELECT
        COALESCE(SUM(calorias_consumidas), 0)::int AS calorias,
        COALESCE(SUM(proteinas_g), 0)::numeric      AS proteinas,
        COALESCE(SUM(carbohidratos_g), 0)::numeric  AS carbohidratos,
        COALESCE(SUM(grasas_g), 0)::numeric         AS grasas,
        COUNT(*)::int                               AS items
       FROM registros_nutricion
      WHERE usuario_id = $1 AND fecha = CURRENT_DATE`,
    [usuarioId],
  );
  const agua = await query(
    `SELECT COALESCE(total_ml, 0)::int AS total_ml
       FROM registros_hidratacion
      WHERE usuario_id = $1 AND fecha = CURRENT_DATE`,
    [usuarioId],
  );
  const f = foods.rows[0] || {};
  return {
    calorias:       Number(f.calorias || 0),
    proteinas:      Number(f.proteinas || 0),
    carbohidratos:  Number(f.carbohidratos || 0),
    grasas:         Number(f.grasas || 0),
    items:          Number(f.items || 0),
    agua_ml:        Number(agua.rows[0]?.total_ml || 0),
  };
}

/** Lista de alimentos consumidos hoy (para marcar checks en la app). */
async function getTodayEntries(usuarioId) {
  const r = await query(
    `SELECT id, comida, nombre_alimento, cantidad_gramos,
            calorias_consumidas, proteinas_g, carbohidratos_g, grasas_g
       FROM registros_nutricion
      WHERE usuario_id = $1 AND fecha = CURRENT_DATE
      ORDER BY creado_en ASC`,
    [usuarioId],
  );
  return r.rows;
}

/** Registra un alimento consumido HOY. @returns {Promise<object>} fila creada. */
async function logFood(usuarioId, {
  comida, nombreAlimento, cantidadGramos,
  calorias = 0, proteinas = 0, carbohidratos = 0, grasas = 0, codigoBarras = null,
}) {
  const r = await query(
    `INSERT INTO registros_nutricion
        (usuario_id, fecha, comida, codigo_barras, nombre_alimento, cantidad_gramos,
         calorias_consumidas, proteinas_g, carbohidratos_g, grasas_g)
     VALUES ($1, CURRENT_DATE, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING id, comida, nombre_alimento, cantidad_gramos,
               calorias_consumidas, proteinas_g, carbohidratos_g, grasas_g`,
    [
      usuarioId, normComida(comida), codigoBarras,
      String(nombreAlimento || 'Alimento').slice(0, 300),
      Number(cantidadGramos) > 0 ? Number(cantidadGramos) : 1,
      Number(calorias) || 0, Number(proteinas) || 0, Number(carbohidratos) || 0, Number(grasas) || 0,
    ],
  );
  return r.rows[0];
}

/** Elimina un registro consumido del día del usuario. @returns {boolean} */
async function deleteFood(usuarioId, id) {
  const r = await query(
    `DELETE FROM registros_nutricion
      WHERE id = $1 AND usuario_id = $2 AND fecha = CURRENT_DATE`,
    [id, usuarioId],
  );
  return r.rowCount > 0;
}

/** Suma agua (ml) al total de HOY (upsert). @returns {number} nuevo total_ml. */
async function addWater(usuarioId, ml) {
  const delta = Math.max(0, parseInt(ml, 10) || 0);
  const r = await query(
    `INSERT INTO registros_hidratacion (usuario_id, fecha, total_ml, actualizado_en)
     VALUES ($1, CURRENT_DATE, $2, now())
     ON CONFLICT (usuario_id, fecha)
       DO UPDATE SET total_ml = registros_hidratacion.total_ml + EXCLUDED.total_ml,
                     actualizado_en = now()
     RETURNING total_ml`,
    [usuarioId, delta],
  );
  return Number(r.rows[0]?.total_ml || 0);
}

/** Fija el agua del día a un valor exacto (para correcciones). @returns {number} */
async function setWater(usuarioId, ml) {
  const total = Math.max(0, parseInt(ml, 10) || 0);
  const r = await query(
    `INSERT INTO registros_hidratacion (usuario_id, fecha, total_ml, actualizado_en)
     VALUES ($1, CURRENT_DATE, $2, now())
     ON CONFLICT (usuario_id, fecha)
       DO UPDATE SET total_ml = EXCLUDED.total_ml, actualizado_en = now()
     RETURNING total_ml`,
    [usuarioId, total],
  );
  return Number(r.rows[0]?.total_ml || 0);
}

module.exports = {
  getTodaySummary,
  getTodayEntries,
  logFood,
  deleteFood,
  addWater,
  setWater,
};
