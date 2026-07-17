/**
 * @file services/access-service/src/config/database.js
 * @description Cliente Supabase singleton para access_service_db.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('access-service:db');

let supabaseClient = null;

function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;
  supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-access-service' } },
  });
  logger.info('Supabase conectado', { schema: env.SUPABASE_DB_SCHEMA });
  return supabaseClient;
}

async function checkDatabaseConnection() {
  try {
    const db = getSupabaseClient();
    const { error } = await db.from('historial_accesos').select('id').limit(1);
    if (error) throw error;
    return true;
  } catch (err) {
    logger.error('Fallo en conexión a Supabase', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection };
