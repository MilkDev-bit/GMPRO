/**
 * @file services/payment-service/src/config/stripe.js
 * @description Inicialización del SDK de Stripe con configuración de producción.
 *
 * Stripe SDK se instancia una sola vez (singleton) con las opciones óptimas
 * para un entorno de producción:
 *   • apiVersion fija: evita breaking changes automáticos cuando Stripe actualiza su API
 *   • maxNetworkRetries: reintentos automáticos para errores de red transitorios
 *   • timeout: previene que un request colgado bloquee el servidor
 *   • telemetry: deshabilitado en producción (privacidad)
 */

'use strict';

const Stripe = require('stripe');
const env    = require('./environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('payment-service:stripe');

// Versión de la API de Stripe fijada explícitamente.
// IMPORTANTE: Actualizar solo después de revisar el changelog de Stripe y
// probar en modo test. Un cambio de versión puede alterar la estructura
// de los eventos del webhook.
const STRIPE_API_VERSION = '2024-11-20.acacia';

let stripeInstance = null;

/**
 * Retorna la instancia singleton de Stripe.
 * @returns {import('stripe').Stripe}
 */
function getStripeClient() {
  if (stripeInstance) return stripeInstance;

  stripeInstance = new Stripe(env.STRIPE_SECRET_KEY, {
    apiVersion:        STRIPE_API_VERSION,
    maxNetworkRetries: 3,        // Reintentos automáticos para errores 500/503 de Stripe
    timeout:           30_000,   // 30 segundos — cancelar si Stripe no responde
    telemetry:         false,    // No enviar datos de uso a Stripe (privacidad)
    appInfo: {
      name:    'GymPro',
      version: '1.0.0',
      url:     'https://gympro.app',
    },
  });

  logger.info('Stripe SDK inicializado', {
    apiVersion: STRIPE_API_VERSION,
    mode:       env.STRIPE_SECRET_KEY.startsWith('sk_live') ? 'LIVE' : 'TEST',
  });

  return stripeInstance;
}

module.exports = { getStripeClient, STRIPE_API_VERSION };
