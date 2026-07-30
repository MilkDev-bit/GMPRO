/**
 * @file services/auth-service/src/config/database.js
 * @description Cliente Supabase para auth-service.
 *
 * Usa la SERVICE_ROLE_KEY (bypasea RLS) porque el microservicio es el
 * único responsable de su propio schema. RLS se configura en Supabase
 * como capa adicional para clientes directos, no para el backend.
 *
 * El cliente se crea una sola vez (singleton) y se reutiliza en toda la app.
 */

'use strict';

const { createClient } = require('@supabase/supabase-js');
const { Pool } = require('pg');
const env = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('auth-service:db');

let supabaseClient = null;

/**
 * Retorna el cliente Supabase singleton.
 * Inicializado con la SERVICE_ROLE_KEY para acceso total al schema.
 *
 * @returns {import('@supabase/supabase-js').SupabaseClient}
 */
function getSupabaseClient() {
  if (supabaseClient) return supabaseClient;

  supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      // Deshabilitar persistencia de sesión del cliente JS (no la necesitamos en backend)
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    db: {
      // Apuntar al schema propio de este microservicio
      schema: env.SUPABASE_DB_SCHEMA,
    },
    global: {
      headers: {
        // Header de identificación del cliente para logs de Supabase
        'x-app-name': 'gympro-auth-service',
      },
    },
  });

  logger.info('Cliente Supabase inicializado', {
    schema: env.SUPABASE_DB_SCHEMA,
    url:    env.SUPABASE_URL.replace(/https:\/\/(.{4}).*\.supabase\.co/, 'https://$1***.supabase.co'),
  });

  return supabaseClient;
}

/**
 * Verifica que la conexión a Supabase esté activa.
 * Usada en el healthcheck extendido (/ready).
 *
 * @returns {Promise<boolean>}
 */
// ── pg directo (mínimo privilegio, CLD-1): rol svc_auth ──────────────────────
// Los modelos MIGRADOS usan query(); durante la transición getSupabaseClient()
// (service_role) sigue disponible para lo no migrado. Cuando TODO use query(),
// se retira supabase-js de auth.
let pgPool = null;
function getPool() {
  if (pgPool) return pgPool;
  if (!env.AUTH_DATABASE_URL) {
    throw new Error('AUTH_DATABASE_URL no configurada (conexión pg del rol svc_auth).');
  }
  // pg-connection-string trata sslmode=require como verify-full → rechaza el cert
  // self-signed del pooler de Supabase. Lo quitamos y forzamos TLS por el objeto ssl.
  const connectionString = env.AUTH_DATABASE_URL.replace(/[?&]sslmode=[^&]+/i, '');
  pgPool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },           // Supabase exige TLS (cadena self-signed)
    max: 10,
    options: '-c search_path=auth_service_db',     // el pooler no aplica el search_path del rol
  });
  pgPool.on('error', (err) => logger.error('Error en pool pg de auth', { error: err.message }));
  logger.info('Pool pg (svc_auth) inicializado');
  return pgPool;
}

/**
 * Ejecuta SQL PARAMETRIZADO con el rol svc_auth (nunca concatenar valores).
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
  return getPool().query(text, params);
}

async function checkDatabaseConnection() {
  try {
    await query('SELECT 1');   // salud vía pg (rol svc_auth)
    return true;
  } catch (err) {
    logger.error('Fallo en verificación de conexión pg (svc_auth)', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection, query, getPool };
