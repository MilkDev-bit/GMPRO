/**
 * @file services/access-service/src/config/database.js
 * @description Cliente Supabase singleton para access_service_db.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const jwt = require('jsonwebtoken');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('access-service:db');

const SVC_ROLE = 'svc_access';
// Mínimo privilegio (CLD-1) con COEXISTENCIA: con SUPABASE_JWT_SECRET + ANON_KEY el
// cliente se autentica con un JWT role=svc_access → PostgREST hace SET ROLE y aplican
// RLS + policies. Si faltan, cae al SERVICE_ROLE_KEY (god-mode). Activable por env.
const useScopedRole = !!(env.SUPABASE_JWT_SECRET && env.SUPABASE_ANON_KEY);
const TOKEN_TTL_SEC  = 60 * 60;
const REFRESH_MARGIN = 10 * 60 * 1000;

let supabaseClient = null;
let tokenIssuedAt  = 0;

function scopedRoleToken() {
  return jwt.sign({ role: SVC_ROLE, iss: 'gympro-access-service' }, env.SUPABASE_JWT_SECRET, { expiresIn: TOKEN_TTL_SEC });
}

function buildClient() {
  if (useScopedRole) {
    tokenIssuedAt = Date.now();
    logger.info('Supabase conectado (rol de mínimo privilegio)', { schema: env.SUPABASE_DB_SCHEMA, role: SVC_ROLE });
    return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      db:   { schema: env.SUPABASE_DB_SCHEMA },
      global: { headers: { 'x-app-name': 'gympro-access-service', Authorization: `Bearer ${scopedRoleToken()}` } },
    });
  }
  logger.info('Supabase conectado (service_role — sin rol scopeado)', { schema: env.SUPABASE_DB_SCHEMA });
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-access-service' } },
  });
}

function getSupabaseClient() {
  const stale = useScopedRole && (Date.now() - tokenIssuedAt) > (TOKEN_TTL_SEC * 1000 - REFRESH_MARGIN);
  if (!supabaseClient || stale) supabaseClient = buildClient();
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
