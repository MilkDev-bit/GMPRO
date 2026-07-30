/**
 * @file services/fitness-service/src/config/database.js
 * @description Cliente Supabase singleton para fitness_service_db.
 */
'use strict';

const { createClient } = require('@supabase/supabase-js');
const jwt = require('jsonwebtoken');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');
const logger = createServiceLogger('fitness-service:db');

const SVC_ROLE = 'svc_fitness';
// Mínimo privilegio (CLD-1) con COEXISTENCIA: si hay SUPABASE_JWT_SECRET + ANON_KEY,
// el cliente se autentica con un JWT que fija role=svc_fitness → PostgREST hace
// SET ROLE y aplican RLS + policies. Si faltan, cae al SERVICE_ROLE_KEY de siempre
// (god-mode). Así se puede desplegar sin romper y activar por variable de entorno.
const useScopedRole = !!(env.SUPABASE_JWT_SECRET && env.SUPABASE_ANON_KEY);
const TOKEN_TTL_SEC   = 60 * 60;              // vida del JWT de servicio (1h)
const REFRESH_MARGIN  = 10 * 60 * 1000;       // recrear el cliente 10 min antes de expirar

let supabaseClient = null;
let tokenIssuedAt  = 0;

function scopedRoleToken() {
  // JWT firmado con el secreto del proyecto; PostgREST lee el claim `role` y hace SET ROLE.
  return jwt.sign(
    { role: SVC_ROLE, iss: 'gympro-fitness-service' },
    env.SUPABASE_JWT_SECRET,
    { expiresIn: TOKEN_TTL_SEC },
  );
}

function buildClient() {
  if (useScopedRole) {
    tokenIssuedAt = Date.now();
    logger.info('Supabase conectado (rol de mínimo privilegio)', { schema: env.SUPABASE_DB_SCHEMA, role: SVC_ROLE });
    return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      db:   { schema: env.SUPABASE_DB_SCHEMA },
      global: { headers: { 'x-app-name': 'gympro-fitness-service', Authorization: `Bearer ${scopedRoleToken()}` } },
    });
  }
  logger.info('Supabase conectado (service_role — sin rol scopeado)', { schema: env.SUPABASE_DB_SCHEMA });
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    db:   { schema: env.SUPABASE_DB_SCHEMA },
    global: { headers: { 'x-app-name': 'gympro-fitness-service' } },
  });
}

function getSupabaseClient() {
  // Con rol scopeado, el JWT va horneado en el cliente → recrearlo antes de que expire.
  const stale = useScopedRole && (Date.now() - tokenIssuedAt) > (TOKEN_TTL_SEC * 1000 - REFRESH_MARGIN);
  if (!supabaseClient || stale) supabaseClient = buildClient();
  return supabaseClient;
}

async function checkDatabaseConnection() {
  try {
    const db = getSupabaseClient();
    const { error } = await db.from('ejercicios').select('id').limit(1);
    if (error && error.code !== 'PGRST116' && error.code !== '42P01') throw error;
    return true;
  } catch (err) {
    logger.error('Fallo en conexión a Supabase (fitness-service)', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection };
