/**
 * @file services/payment-service/src/config/database.js
 * @description Cliente Supabase singleton para payment_service_db.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const { Pool } = require('pg');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('payment-service:db');

let supabaseClient = null;

function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;
  supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-payment-service' } },
  });
  logger.info('Supabase conectado', { schema: env.SUPABASE_DB_SCHEMA });
  return supabaseClient;
}

async function checkDatabaseConnection() {
  try {
    await query('SELECT 1');   // salud vía pg (rol svc_payment)
    return true;
  } catch (err) {
    logger.error('Fallo en conexión pg (svc_payment)', { error: err.message });
    return false;
  }
}

// ── pg directo (mínimo privilegio, CLD-1): rol svc_payment ───────────────────
// Los modelos MIGRADOS usan query(); los aún no migrados siguen con
// getSupabaseClient() (service_role) durante la transición. Cuando TODOS usen
// query(), se retira supabase-js de payment.
let pgPool = null;
function getPool() {
  if (pgPool) return pgPool;
  if (!env.PAYMENT_DATABASE_URL) {
    throw new Error('PAYMENT_DATABASE_URL no configurada (conexión pg del rol svc_payment).');
  }
  // pg-connection-string trata sslmode=require como verify-full → rechaza el cert
  // self-signed del pooler de Supabase y anula el ssl de abajo. Lo quitamos y
  // forzamos TLS sin verificación por el objeto ssl.
  const connectionString = env.PAYMENT_DATABASE_URL.replace(/[?&]sslmode=[^&]+/i, '');
  pgPool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },              // Supabase exige TLS (cadena self-signed)
    max: 10,
    // Sin esto, un problema de red/DB deja la conexión colgada PARA SIEMPRE (default
    // de pg = 0) → la request nunca responde y el cliente corta con "revisa tu
    // conexión" sin dejar rastro. Con el timeout, falla rápido con un error claro.
    connectionTimeoutMillis: 8000,
    idleTimeoutMillis: 30000,
    options: '-c search_path=payment_service_db',    // refuerza el search_path del rol
  });
  pgPool.on('error', (err) => logger.error('Error en pool pg de payment', { error: err.message }));
  logger.info('Pool pg (svc_payment) inicializado');
  return pgPool;
}

/**
 * Ejecuta SQL PARAMETRIZADO con el rol svc_payment (nunca concatenar valores).
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
  return getPool().query(text, params);
}

module.exports = { getSupabaseClient, checkDatabaseConnection, query, getPool };
