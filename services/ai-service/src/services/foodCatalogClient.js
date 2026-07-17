/**
 * @file services/ai-service/src/services/foodCatalogClient.js
 * @description Cliente M2M hacia fitness-service (dueño de `catalogo_alimentos`) para
 * verificar códigos de barras y buscar alimentos por nombre. Respeta el aislamiento
 * de esquemas por microservicio: ai-service NO consulta el schema de fitness
 * directamente, sino su endpoint interno protegido por INTER_SERVICE_SECRET.
 *
 * Provee las dos funciones que espera foodReconciliationService (inyección de
 * dependencias). Degradan a vacío/null ante fallos de red para no bloquear el plan.
 */

'use strict';

const env                     = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('ai-service:foodCatalogClient');

const VERIFY_URL = `${env.FITNESS_SERVICE_INTERNAL_URL}/api/v1/internal/foods/verify`;

async function postVerify(body) {
  const controller = new AbortController();
  const timeoutId  = setTimeout(() => controller.abort(), env.INTER_SERVICE_TIMEOUT_MS || 4000);
  try {
    const response = await fetch(VERIFY_URL, {
      method:  'POST',
      headers: {
        'Content-Type':           'application/json',
        'x-inter-service-secret': env.INTER_SERVICE_SECRET,
        'Accept':                 'application/json',
      },
      body:   JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) return null;
    const json = await response.json();
    return json?.data || null;
  } catch (err) {
    logger.warn('Verificación de alimentos en fitness-service falló (degradando)', { error: err.message });
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Verifica un lote de códigos de barras contra el catálogo local.
 * @param {string[]} codes
 * @returns {Promise<Map<string, object>>}
 */
async function lookupByBarcodes(codes) {
  const map = new Map();
  if (!Array.isArray(codes) || codes.length === 0) return map;
  const data = await postVerify({ barcodes: codes });
  const byBarcode = data?.by_barcode || {};
  for (const [code, food] of Object.entries(byBarcode)) {
    if (food) map.set(code, food);
  }
  return map;
}

/**
 * Busca un alimento por nombre en el catálogo local.
 * @param {string} name
 * @returns {Promise<object|null>}
 */
async function lookupByName(name) {
  if (!name) return null;
  const data = await postVerify({ name });
  return data?.by_name || null;
}

module.exports = { lookupByBarcodes, lookupByName };
