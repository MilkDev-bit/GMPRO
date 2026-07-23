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
const { notifyBiometricDelete } = require('./biometricNotificationService');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:growthWorker');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:3004';
// ⚠ CWE-798: antes había aquí una API key de producción hardcodeada como
// fallback ('turnstile_secret_key_prod_2026'). Eliminada: si falta la
// variable, se deja vacío y la llamada M2M fallará con 401 de forma
// controlada, en lugar de operar con un secreto conocido y versionado.
const TURNSTILE_KEY  = process.env.TURNSTILE_API_KEY || '';

// Zona horaria del gimnasio para el corte por fecha. `valido_hasta` es un
// DATE sin hora ni zona; "hoy" debe evaluarse en la TZ del negocio, no en
// UTC, o se revocaría/renovaría con hasta un día de desfase. Configurable.
const BUSINESS_TZ = process.env.BUSINESS_TIMEZONE || 'America/Mexico_City';

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
/**
 * ── 3. REVOCACIÓN DE ACCESO FACIAL POR VENCIMIENTO (grace period = 0) ───────
 *
 * Audita 2.3: el acceso facial ZKTeco decide localmente en el dispositivo
 * (TZ=24/7) y solo se borraba en customer.subscription.deleted (fin del
 * dunning de Stripe, 7-14 días después del vencimiento). Este proceso cierra
 * esa ventana: revoca el acceso facial en cuanto `valido_hasta` queda en el
 * pasado, equiparando la estrictez del camino QR (que valida vigencia en vivo).
 *
 * CRITERIO DE CORTE (operador `<`, no `<=`):
 *   valido_hasta es la ÚLTIMA fecha válida (inclusive). Un socio "válido
 *   hasta el 28" conserva acceso el día 28 y se revoca el 29. Por eso la
 *   condición es `valido_hasta < hoy`: un valido_hasta futuro nunca entra;
 *   el propio día de vencimiento tampoco (aún es válido).
 *
 * DESFASE TEMPORAL (limitación conocida, no bug): el worker corre por
 * setInterval cada ~6h sobre el uptime del proceso, no como cron a hora
 * fija. Entre el vencimiento real (medianoche TZ del negocio) y la
 * revocación efectiva pueden pasar hasta ~6h. Para revocación instantánea
 * al minuto exacto haría falta un trigger por evento, no un barrido
 * periódico — fuera del alcance de esta corrección.
 *
 * IDEMPOTENCIA: se filtra `acceso_facial_revocado_en IS NULL` y se sella al
 * revocar con éxito. Un usuario ya revocado NO recibe un DELETE nuevo cada
 * corrida. El flag se limpia al reactivar (subscriptionModel.activateAfterPayment).
 *
 * FALLOS POR USUARIO: si notifyBiometricDelete falla (terminal offline,
 * timeout), NO se sella el flag y NO se aborta el lote: se registra y se
 * continúa. Al quedar sin sellar, el siguiente ciclo (~6h) lo reintenta
 * automáticamente. No requiere intervención manual.
 */
async function processExpiredFacialRevocation() {
  const db = getSupabaseClient();

  // "Hoy" en la zona horaria del negocio, como fecha pura YYYY-MM-DD, para
  // comparar contra el DATE `valido_hasta` sin arrastrar hora ni UTC.
  const hoyLocal = new Intl.DateTimeFormat('en-CA', {
    timeZone: BUSINESS_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date()); // en-CA => 'YYYY-MM-DD'

  logger.info('🔒 [GrowthWorker] Escaneo de revocación facial por vencimiento…', {
    corteAntesDe: hoyLocal, tz: BUSINESS_TZ,
  });

  // Estados en INGLÉS: son los que el código realmente escribe
  // (active/past_due/cancelled). Se excluye 'active' y 'free_pass' —el socio
  // vigente o de pase libre no se toca— y se exige que el período pagado ya
  // haya terminado.
  const { data: vencidas, error } = await db
    .from('suscripciones')
    .select('id, usuario_id, valido_hasta, estado')
    .lt('valido_hasta', hoyLocal)               // operador `<` (ver criterio arriba)
    .not('estado', 'in', '("active","free_pass")')
    .is('acceso_facial_revocado_en', null)      // idempotencia: no reprocesar
    .limit(500);

  if (error) {
    logger.error('Error consultando suscripciones vencidas para revocación facial', {
      error: error.message,
    });
    return;
  }
  if (!vencidas || vencidas.length === 0) {
    logger.info('✅ Ninguna membresía vencida pendiente de revocación facial.');
    return;
  }

  logger.warn(`🚨 ${vencidas.length} membresía(s) vencida(s) con acceso facial por revocar.`);

  let revocadas = 0;
  let fallidas  = 0;

  for (const sub of vencidas) {
    try {
      // pin_terminal vive en usuarios (mismo patrón que getUserBiometricInfo).
      const { data: user, error: userErr } = await db
        .from('usuarios')
        .select('id, pin_terminal')
        .eq('id', sub.usuario_id)
        .single();

      if (userErr || !user) {
        // Sin usuario no hay a quién revocar en el terminal. Se sella igual
        // para no reintentar indefinidamente sobre un registro huérfano.
        logger.warn('Usuario no encontrado para revocación facial; se sella sin DELETE', {
          suscripcionId: sub.id, usuarioId: sub.usuario_id,
        });
        await _sellarRevocacion(db, sub.id);
        continue;
      }

      if (!user.pin_terminal) {
        // Nunca tuvo acceso facial (sin PIN de terminal). Nada que borrar;
        // se sella para excluirlo de futuros barridos.
        logger.info('Usuario sin pin_terminal; no hay acceso facial que revocar', {
          usuarioId: sub.usuario_id,
        });
        await _sellarRevocacion(db, sub.id);
        continue;
      }

      // DELETE al terminal. notifyBiometricDelete lanza si la llamada M2M
      // falla; en ese caso NO sellamos (se reintenta al próximo ciclo).
      await notifyBiometricDelete(sub.usuario_id, user.pin_terminal);
      await _sellarRevocacion(db, sub.id);
      revocadas++;

      logger.warn('Acceso facial revocado por vencimiento', {
        usuarioId: sub.usuario_id, validoHasta: sub.valido_hasta, estado: sub.estado,
      });
    } catch (err) {
      fallidas++;
      // Un fallo por usuario NO aborta el lote. Al no sellarse, el próximo
      // ciclo (~6h) lo reintenta automáticamente.
      logger.error('Fallo revocando acceso facial; se reintentará el próximo ciclo', {
        suscripcionId: sub.id, usuarioId: sub.usuario_id, error: err.message,
      });
    }
  }

  logger.info('🔒 Revocación facial completada', {
    total: vencidas.length, revocadas, fallidas,
  });
}

/** Sella la marca de idempotencia tras revocar (o descartar) un usuario. */
async function _sellarRevocacion(db, suscripcionId) {
  const { error } = await db
    .from('suscripciones')
    .update({ acceso_facial_revocado_en: new Date().toISOString() })
    .eq('id', suscripcionId);
  if (error) {
    // Si no se puede sellar, se reintentará (no rompe el flujo): mejor un
    // DELETE repetido —inocuo en el terminal— que dejar de revocar.
    logger.warn('No se pudo sellar acceso_facial_revocado_en', {
      suscripcionId, error: error.message,
    });
  }
}

async function runGrowthCycle() {
  logger.info('🚀 [GrowthRetentionWorker] Iniciando ciclo de retención y monitoreo en Supabase...');
  await processPastDueRecovery();
  await processInactivityAlerts();
  await processExpiredFacialRevocation();
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
  processExpiredFacialRevocation,
  runGrowthCycle,
  startCronDaemon,
};
