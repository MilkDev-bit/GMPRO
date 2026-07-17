/**
 * @file services/payment-service/src/services/growthRetentionWorker.js
 * @description Worker asíncrono y tarea Cron de Crecimiento (Growth) y Retención.
 * Monitorea los esquemas en Supabase para:
 *   1. Recuperación de Membresía (`past_due`): dispara webhook al ai-service para copy persuasivo
 *      y envía push notification y email con deepLink hacia la pantalla de ajustes de cobro.
 *   2. Alerta de Inactividad (5 días sin acceso en `historial_accesos`): genera una rutina suave
 *      de reactivación vía IA y la envía en un correo motivacional automatizado.
 */

'use strict';

const axios                   = require('axios');
const { getSupabaseClient }   = require('../config/database');
const emailService            = require('./emailService');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:growthWorker');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:3004';
const TURNSTILE_KEY  = process.env.TURNSTILE_API_KEY || 'turnstile_secret_key_prod_2026';

/**
 * ── 1. RECUPERACIÓN DE MEMBRESÍA (`past_due`) ───────────────────────────────
 * Identifica suscripciones vencidas/fallidas y envía notificación persuasiva.
 */
async function processPastDueRecovery() {
  const db = getSupabaseClient();
  const ahora = new Date();
  const tresDiasAtras = new Date(ahora.getTime() - 3 * 24 * 60 * 60 * 1000).toISOString();

  logger.info('🔍 [GrowthWorker] Iniciando escaneo de recuperación de membresías past_due...');

  try {
    // Buscar suscripciones en past_due no notificadas o cuyo último aviso tiene > 3 días
    const { data: pastDueSubs, error: subError } = await db
      .from('suscripciones')
      .select('id, usuario_id, plan_nombre, monto, notificado_recuperacion_en')
      .eq('estado', 'past_due')
      .or(`notificado_recuperacion_en.is.null,notificado_recuperacion_en.lt.${tresDiasAtras}`);

    if (subError) throw subError;
    if (!pastDueSubs || pastDueSubs.length === 0) {
      logger.info('✅ Ninguna membresía past_due requiere notificación el día de hoy.');
      return;
    }

    logger.info(`🚨 Encontradas ${pastDueSubs.length} membresías en past_due por recuperar.`);

    for (const sub of pastDueSubs) {
      try {
        // Obtener datos del usuario
        const { data: user, error: userError } = await db
          .from('usuarios')
          .select('id, nombre, email, push_token')
          .eq('id', sub.usuario_id)
          .single();

        if (userError || !user) {
          logger.warn(`No se encontró usuario ${sub.usuario_id} para suscripción ${sub.id}`);
          continue;
        }

        const nombre = user.nombre || 'Socio GymPro';
        let pushCopy = `¡Hola, ${nombre}! Tu membresía ${sub.plan_nombre || 'Pro'} requiere actualizar el método de pago. Toca aquí para renovar al instante sin perder tu racha.`;

        // 1. Consultar al ai-service para redactar un copy ultra persuasivo
        try {
          const aiResponse = await axios.post(
            `${AI_SERVICE_URL}/api/v1/recommendations/notification`,
            {
              usuario_id: user.id,
              nombre:     nombre,
              tipo:       'payment_recovery',
              plan:       sub.plan_nombre || 'GymPro Premium',
              monto:      sub.monto || 499,
            },
            {
              headers: { 'X-Turnstile-API-Key': TURNSTILE_KEY, 'Content-Type': 'application/json' },
              timeout: 4000,
            }
          );
          if (aiResponse.data?.success && aiResponse.data?.data?.copy) {
            pushCopy = aiResponse.data.data.copy;
          }
        } catch (aiErr) {
          logger.warn(`Fallback copy (ai-service no disponible para push recovery): ${aiErr.message}`);
        }

        // 2. Enviar Push Notification (simulada/disparada por FCM o servicio de notificaciones)
        logger.info(`📲 [PUSH ENVIADA] a ${user.email} (Token: ${user.push_token || 'simulado'}): "${pushCopy}" | deepLink: gympro://settings/billing`);

        // 3. Enviar correo transaccional de recuperación de cobro
        if (user.email) {
          await emailService.sendPaymentRecoveryEmail({
            email:      user.email,
            nombre:     nombre,
            planNombre: sub.plan_nombre,
            monto:      sub.monto,
            deepLink:   'gympro://settings/billing',
          });
        }

        // 4. Actualizar timestamp para control de anti-spam
        await db
          .from('suscripciones')
          .update({ notificado_recuperacion_en: ahora.toISOString() })
          .eq('id', sub.id);

        logger.info(`✅ Recuperación procesada exitosamente para socio: ${nombre} (${user.id})`);
      } catch (itemErr) {
        logger.error(`Error procesando recuperación para suscripción ${sub.id}:`, itemErr.message);
      }
    }
  } catch (err) {
    logger.error('Error global en processPastDueRecovery:', err.message);
  }
}

/**
 * ── 2. ALERTA DE INACTIVIDAD (5 DÍAS SIN ACCESO EN `historial_accesos`) ─────
 * Previene la deserción (churn) enviando rutinas suaves motivacionales vía IA.
 */
async function processInactivityAlerts() {
  const db = getSupabaseClient();
  const ahora = new Date();
  const cincoDiasAtras = new Date(ahora.getTime() - 5 * 24 * 60 * 60 * 1000).toISOString();
  const sieteDiasAtras = new Date(ahora.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();

  logger.info('🔍 [GrowthWorker] Verificando historial de accesos de socios activos (últimos 5 días)...');

  try {
    // 1. Obtener socios con membresía ACTIVA
    const { data: activeSubs, error: subError } = await db
      .from('suscripciones')
      .select('id, usuario_id, notificado_inactividad_en')
      .eq('estado', 'active')
      .or(`notificado_inactividad_en.is.null,notificado_inactividad_en.lt.${sieteDiasAtras}`);

    if (subError) throw subError;
    if (!activeSubs || activeSubs.length === 0) {
      logger.info('✅ Todos los socios activos están al día o ya fueron motivados recientemente.');
      return;
    }

    logger.info(`📊 Analizando ${activeSubs.length} suscripciones activas para detectar inactividad...`);

    let inactivosDetectados = 0;

    for (const sub of activeSubs) {
      try {
        // 2. Consultar si hay alguna entrada en historial_accesos en los últimos 5 días
        const { data: accesos, error: accesoError } = await db
          .from('historial_accesos')
          .select('id')
          .eq('usuario_id', sub.usuario_id)
          .gte('fecha_acceso', cincoDiasAtras)
          .limit(1);

        if (accesoError) {
          // Si la tabla no existe o falla en entorno de desarrollo local, continuar de forma segura
          if (accesoError.code === '42P01') {
            logger.warn('Tabla historial_accesos no encontrada. Saltando verificación de inactividad.');
            break;
          }
          throw accesoError;
        }

        // Si tiene al menos 1 acceso en los últimos 5 días, está activo; pasar al siguiente
        if (accesos && accesos.length > 0) {
          continue;
        }

        inactivosDetectados++;

        // 3. El usuario lleva >= 5 días inactivo. Obtener perfil para personalizar rutina de reactivación.
        const { data: user, error: userError } = await db
          .from('usuarios')
          .select('id, nombre, email, objetivo_fitness, lesiones')
          .eq('id', sub.usuario_id)
          .single();

        if (userError || !user || !user.email) continue;

        const nombre = user.nombre || 'Socio GymPro';
        logger.info(`😴 Socio inactivo detectado: ${nombre} (${user.id}). Generando rutina de regreso por IA...`);

        // 4. Solicitar al ai-service una rutina motivacional suave de 20 minutos según su historial/objetivo
        let rutinaHtml = `
          <ul style="padding-left: 20px; color: #E0E0E0;">
            <li style="margin-bottom: 8px;">🔥 <strong>Movilidad Articular (5 min):</strong> Giros suaves y estiramiento activo.</li>
            <li style="margin-bottom: 8px;">🏋️ <strong>Circuito Suave (10 min):</strong> 3 series de sentadillas al aire (10 reps) + lagartijas en inclinación (10 reps).</li>
            <li style="margin-bottom: 8px;">🚶 <strong>Cardio Ligero (5 min):</strong> Caminata en pendiente al 6% a ritmo constante.</li>
          </ul>
        `;

        try {
          const aiResponse = await axios.post(
            `${AI_SERVICE_URL}/api/v1/recommendations/reactivation-routine`,
            {
              usuario_id:       user.id,
              nombre:           nombre,
              objetivo:         user.objetivo_fitness || 'salud general',
              lesiones:         user.lesiones || 'ninguna',
              dias_inactivos:   5,
              duracion_minutos: 20,
            },
            {
              headers: { 'X-Turnstile-API-Key': TURNSTILE_KEY, 'Content-Type': 'application/json' },
              timeout: 5000,
            }
          );

          if (aiResponse.data?.success && aiResponse.data?.data?.rutina_html) {
            rutinaHtml = aiResponse.data.data.rutina_html;
          }
        } catch (aiErr) {
          logger.warn(`Using fallback reactivation routine (ai-service offline): ${aiErr.message}`);
        }

        // 5. Enviar correo motivacional automatizado (vía emailService.js)
        await emailService.sendReactivationEmail({
          email:      user.email,
          nombre:     nombre,
          rutinaHtml: rutinaHtml,
          deepLink:   'gympro://workout/reactivation',
        });

        // 6. Enviar Push Notification de respaldo
        logger.info(`📲 [PUSH MOTIVACIONAL] a ${user.email}: "⚡ ${nombre}, tu cuerpo echa de menos el movimiento. Te preparamos una rutina suave de 20 min. ¡Toca aquí para verla!"`);

        // 7. Marcar como notificado en Supabase para no saturarlo
        await db
          .from('suscripciones')
          .update({ notificado_inactividad_en: ahora.toISOString() })
          .eq('id', sub.id);

        logger.info(`✅ Alerta de inactividad enviada a socio: ${nombre} (${user.id})`);
      } catch (itemErr) {
        logger.error(`Error procesando inactividad para socio ${sub.usuario_id}:`, itemErr.message);
      }
    }

    logger.info(`📊 Escaneo finalizado. Socios inactivos notificados: ${inactivosDetectados}`);
  } catch (err) {
    logger.error('Error global en processInactivityAlerts:', err.message);
  }
}

/**
 * ── 3. ORQUESTADOR Y TAREA CRON ─────────────────────────────────────────────
 * Ejecuta un ciclo completo de verificación.
 */
async function runGrowthCycle() {
  logger.info('🚀 [GrowthRetentionWorker] Iniciando ciclo de retención y monitoreo en Supabase...');
  await processPastDueRecovery();
  await processInactivityAlerts();
  logger.info('🏁 [GrowthRetentionWorker] Ciclo completado.');
}

/**
 * Inicia el cron en segundo plano (cada 6 horas por defecto o en intervalo configurado).
 */
function startCronDaemon(intervalMinutes = 360) {
  logger.info(`⏰ Cron de Growth programado para ejecutarse cada ${intervalMinutes} minutos (${intervalMinutes / 60}h).`);
  
  // Ejecutar primera vuelta a los 10 segundos del arranque para inicialización
  setTimeout(() => {
    runGrowthCycle().catch((e) => logger.error('Error en ejecución de runGrowthCycle:', e.message));
  }, 10_000);

  // Programar bucle continuo
  setInterval(() => {
    runGrowthCycle().catch((e) => logger.error('Error en bucle setInterval runGrowthCycle:', e.message));
  }, intervalMinutes * 60 * 1000);
}

// Si se ejecuta directamente vía CLI: `node growthRetentionWorker.js --run-once`
if (require.main === module) {
  require('../config/environment');
  runGrowthCycle()
    .then(() => {
      logger.info('Ejecución CLI terminada.');
      process.exit(0);
    })
    .catch((err) => {
      logger.error('Fallo en ejecución CLI:', err.message);
      process.exit(1);
    });
}

module.exports = {
  processPastDueRecovery,
  processInactivityAlerts,
  runGrowthCycle,
  startCronDaemon,
};
