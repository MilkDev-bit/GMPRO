/**
 * @file services/access-service/src/config/database.js
 * @description Acceso a datos de access_service_db.
 * Mínimo privilegio (CLD-1): pg directo con el rol svc_access.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const { Pool } = require('pg');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('access-service:db');

// ── supabase-js (service_role) sólo para modelos aún no migrados (transición) ──
let supabaseClient = null;
function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;
  supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-access-service' } },
  });
  return supabaseClient;
}

// ── pg directo (svc_access) ──────────────────────────────────────────────────
let pgPool = null;
function getPool() {
  if (pgPool) return pgPool;
  if (!env.ACCESS_DATABASE_URL) {
    throw new Error('ACCESS_DATABASE_URL no configurada (conexión pg del rol svc_access).');
  }
  // pg-connection-string trata sslmode=require como verify-full → rechaza el cert
  // self-signed del pooler de Supabase. Lo quitamos y forzamos TLS por el objeto ssl.
  const connectionString = env.ACCESS_DATABASE_URL.replace(/[?&]sslmode=[^&]+/i, '');
  pgPool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
    max: 10,
    options: '-c search_path=access_service_db',
  });
  pgPool.on('error', (err) => logger.error('Error en pool pg de access', { error: err.message }));
  logger.info('Pool pg (svc_access) inicializado');
  return pgPool;
}

/** SQL parametrizado con el rol svc_access. @returns {Promise<import('pg').QueryResult>} */
async function query(text, params) {
  return getPool().query(text, params);
}

async function checkDatabaseConnection() {
  try {
    await query('SELECT 1');   // salud vía pg (rol svc_access)
    return true;
  } catch (err) {
    logger.error('Fallo en conexión pg (svc_access)', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection, query, getPool };
