/**
 * @file services/fitness-service/src/config/database.js
 * @description Acceso a datos de fitness_service_db.
 * Mínimo privilegio (CLD-1): pg directo con el rol svc_fitness.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const { Pool } = require('pg');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('fitness-service:db');

// ── supabase-js (service_role) sólo para modelos aún no migrados (transición) ──
let supabaseClient = null;
function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;
  supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-fitness-service' } },
  });
  return supabaseClient;
}

// ── pg directo (svc_fitness) ─────────────────────────────────────────────────
let pgPool = null;
function getPool() {
  if (pgPool) return pgPool;
  if (!env.FITNESS_DATABASE_URL) {
    throw new Error('FITNESS_DATABASE_URL no configurada (conexión pg del rol svc_fitness).');
  }
  // pg-connection-string trata sslmode=require como verify-full → rechaza el cert
  // self-signed del pooler de Supabase. Lo quitamos y forzamos TLS por el objeto ssl.
  const connectionString = env.FITNESS_DATABASE_URL.replace(/[?&]sslmode=[^&]+/i, '');
  pgPool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
    max: 10,
    options: '-c search_path=fitness_service_db',
  });
  pgPool.on('error', (err) => logger.error('Error en pool pg de fitness', { error: err.message }));
  logger.info('Pool pg (svc_fitness) inicializado');
  return pgPool;
}

/** SQL parametrizado con el rol svc_fitness. @returns {Promise<import('pg').QueryResult>} */
async function query(text, params) {
  return getPool().query(text, params);
}

async function checkDatabaseConnection() {
  try {
    await query('SELECT 1');   // salud vía pg (rol svc_fitness)
    return true;
  } catch (err) {
    logger.error('Fallo en conexión pg (svc_fitness)', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection, query, getPool };
