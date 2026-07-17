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
async function checkDatabaseConnection() {
  try {
    const db = getSupabaseClient();
    // Query mínima: solo verifica conectividad sin leer datos
    const { error } = await db.from('usuarios').select('id').limit(1);
    if (error) throw error;
    return true;
  } catch (err) {
    logger.error('Fallo en verificación de conexión a Supabase', { error: err.message });
    return false;
  }
}

module.exports = { getSupabaseClient, checkDatabaseConnection };
