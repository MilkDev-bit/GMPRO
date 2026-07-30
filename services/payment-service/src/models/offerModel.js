/**
 * @file services/payment-service/src/models/offerModel.js
 * @description Capa de datos de ofertas/cupones (panel admin).
 * Mínimo privilegio (CLD-1): pg con rol svc_payment, SQL parametrizado.
 */

'use strict';

const { query } = require('../config/database');

const COLUMNS =
  'id, nombre, codigo, tipo, valor, activa, valido_desde, valido_hasta, usos, max_usos, creado_en';

async function listOffers({ limit = 200 } = {}) {
  const { rows } = await query(
    `SELECT ${COLUMNS} FROM ofertas ORDER BY creado_en DESC LIMIT $1`,
    [Math.min(limit, 500)],
  );
  return rows;
}

/**
 * Crea una oferta. Propaga el error con code '23505' si el código ya existe
 * (para que el controlador responda 409).
 */
async function createOffer({ nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos = null }) {
  const { rows } = await query(
    `INSERT INTO ofertas (nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING ${COLUMNS}`,
    [nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos],
  );
  return rows[0];
}

async function setActive(id, activa) {
  const { rows } = await query(
    `UPDATE ofertas SET activa = $2, actualizado_en = $3 WHERE id = $1 RETURNING ${COLUMNS}`,
    [id, activa, new Date().toISOString()],
  );
  if (!rows[0]) throw new Error(`Oferta no encontrada: ${id}`);
  return rows[0];
}

/**
 * Busca una oferta por su código (case-insensitive). Escapa los comodines de
 * LIKE (`_` y `%`) para comparar el código de forma literal.
 * @returns {Promise<object|null>}
 */
async function findByCodigo(codigo) {
  const safe = String(codigo).replace(/([\\%_])/g, '\\$1');
  const { rows } = await query(
    `SELECT ${COLUMNS} FROM ofertas WHERE codigo ILIKE $1 LIMIT 1`,
    [safe],
  );
  return rows[0] || null;
}

/**
 * Incrementa ATÓMICAMENTE el contador de usos vía la función SECURITY DEFINER
 * increment_offer_usage (UPDATE ... SET usos = usos + 1).
 * @returns {Promise<number|null>} nuevo total de usos, o null si el código no existe.
 */
async function incrementOfferUsage(codigo) {
  const { rows } = await query(
    `SELECT payment_service_db.increment_offer_usage($1) AS result`,
    [codigo],
  );
  return rows[0].result ?? null;
}

module.exports = { listOffers, createOffer, setActive, findByCodigo, incrementOfferUsage };
