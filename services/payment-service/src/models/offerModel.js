/**
 * @file services/payment-service/src/models/offerModel.js
 * @description Capa de datos de ofertas/cupones (panel admin).
 */

'use strict';

const { getSupabaseClient } = require('../config/database');

const TABLE = 'ofertas';
const COLUMNS =
  'id, nombre, codigo, tipo, valor, activa, valido_desde, valido_hasta, usos, max_usos, creado_en';

async function listOffers({ limit = 200 } = {}) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .select(COLUMNS)
    .order('creado_en', { ascending: false })
    .limit(Math.min(limit, 500));
  if (error) throw error;
  return data || [];
}

/**
 * Crea una oferta. Lanza un error con code '23505' si el código ya existe
 * (para que el controlador responda 409).
 */
async function createOffer({ nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos = null }) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .insert({ nombre, codigo, tipo, valor, valido_desde, valido_hasta, max_usos })
    .select(COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

async function setActive(id, activa) {
  const db = getSupabaseClient();
  const { data, error } = await db
    .from(TABLE)
    .update({ activa, actualizado_en: new Date().toISOString() })
    .eq('id', id)
    .select(COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

/**
 * Busca una oferta por su código (case-insensitive). Escapa los comodines de
 * LIKE (`_` y `%`) para que el código se compare de forma literal — de lo
 * contrario `SUMMER_2026` podría hacer match con `SUMMERX2026`.
 * @returns {Promise<object|null>}
 */
async function findByCodigo(codigo) {
  const db = getSupabaseClient();
  const safe = String(codigo).replace(/([\\%_])/g, '\\$1');
  const { data, error } = await db
    .from(TABLE)
    .select(COLUMNS)
    .ilike('codigo', safe)
    .maybeSingle();
  if (error && error.code !== 'PGRST116') throw error;
  return data || null;
}

/**
 * Incrementa ATÓMICAMENTE el contador de usos (canje) vía la función SQL
 * increment_offer_usage (UPDATE ... SET usos = usos + 1). Evita condiciones de
 * carrera entre canjes concurrentes del mismo código.
 * @returns {Promise<number|null>} nuevo total de usos, o null si el código no existe.
 */
async function incrementOfferUsage(codigo) {
  const db = getSupabaseClient();
  const { data, error } = await db.rpc('increment_offer_usage', { p_codigo: codigo });
  if (error) throw error;
  return data ?? null;
}

module.exports = { listOffers, createOffer, setActive, findByCodigo, incrementOfferUsage };
