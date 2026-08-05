/**
 * @file services/payment-service/tests/integration/webhookIdempotency.integration.test.js
 * @description INTEGRACIÓN contra Postgres REAL: idempotencia ATÓMICA del claim
 *              de webhooks de Stripe bajo concurrencia (re-entrega at-least-once).
 *
 * Prueba la garantía que evita el doble-aprovisionamiento: si N entregas del
 * MISMO evt_… llegan simultáneamente, SOLO UNA reclama (INSERT con PK →
 * violación 23505 en las demás). Es la propiedad de la que depende que un pago
 * no active una suscripción dos veces.
 *
 * La función replica EXACTAMENTE el SQL de subscriptionModel.claimWebhookEvent
 * (INSERT con PRIMARY KEY; 23505 → duplicado). La atomicidad es una propiedad de
 * la restricción PK de Postgres, idéntica por supabase-js o por pg directo.
 *
 * Se salta si no hay DATABASE_URL (suite unitaria normal).
 */

'use strict';

const HAS_DB = !!process.env.DATABASE_URL;
let Pool;
if (HAS_DB) ({ Pool } = require('pg'));

(HAS_DB ? describe : describe.skip)('INTEGRACIÓN — idempotencia atómica de webhook (Postgres real)', () => {
  let pool;

  // Réplica EXACTA de subscriptionModel.claimWebhookEvent
  async function claimWebhookEvent(eventId, tipo) {
    try {
      await pool.query(
        'INSERT INTO webhook_events_procesados (event_id, tipo) VALUES ($1, $2)', [eventId, tipo]);
      return { claimed: true };
    } catch (e) {
      if (e.code === '23505') return { claimed: false }; // PK conflict → duplicado seguro
      throw e;
    }
  }
  async function releaseWebhookEvent(eventId) {
    await pool.query('DELETE FROM webhook_events_procesados WHERE event_id = $1', [eventId]);
  }

  beforeAll(async () => {
    const rawUrl = process.env.DATABASE_URL || '';
    const connStr = rawUrl.replace(/[?&]sslmode=[^&]+/i, '');
    // SSL SOLO contra Supabase (exige TLS). Cualquier Postgres de CI/local (el
    // servicio 'postgres' de GitHub Actions, localhost, 127.0.0.1, etc.) NO soporta
    // SSL → hay que desactivarlo o pg lanza "The server does not support SSL connections".
    const needsSsl = /supabase\.(co|com)/i.test(rawUrl) || /sslmode=require/i.test(rawUrl);
    pool = new Pool({
      connectionString: connStr,
      max: 10,   // el Session Pooler de Supabase limita a ~15 clientes; 20 lo excedía
      ssl: needsSsl ? { rejectUnauthorized: false } : false,
    });
    // DDL alineada con la migración 006 (event_id como PRIMARY KEY).
    await pool.query(`
      CREATE TABLE IF NOT EXISTS webhook_events_procesados (
        event_id     VARCHAR(80) PRIMARY KEY,
        tipo         VARCHAR(80),
        procesado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );`);
  });
  afterAll(async () => { await pool.end(); });
  beforeEach(async () => { await pool.query('TRUNCATE webhook_events_procesados'); });

  test('N entregas concurrentes del MISMO evento → exactamente 1 reclama', async () => {
    const eventId = 'evt_test_concurrent_1';
    const N = 20;
    const results = await Promise.all(
      Array.from({ length: N }, () => claimWebhookEvent(eventId, 'invoice.paid'))
    );
    const claimed = results.filter((r) => r.claimed).length;
    expect(claimed).toBe(1);                    // solo una entrega procesa → sin doble cobro/alta
    expect(results.length - claimed).toBe(N - 1);

    const { rows } = await pool.query(
      'SELECT COUNT(*)::int AS c FROM webhook_events_procesados WHERE event_id = $1', [eventId]);
    expect(rows[0].c).toBe(1);
  });

  test('eventos distintos reclaman de forma independiente', async () => {
    expect((await claimWebhookEvent('evt_a', 'invoice.paid')).claimed).toBe(true);
    expect((await claimWebhookEvent('evt_b', 'customer.subscription.updated')).claimed).toBe(true);
  });

  test('release tras fallo del handler permite el reintento de Stripe', async () => {
    const eventId = 'evt_retry';
    expect((await claimWebhookEvent(eventId, 'invoice.paid')).claimed).toBe(true);
    // Reintento sin liberar → duplicado (idempotente).
    expect((await claimWebhookEvent(eventId, 'invoice.paid')).claimed).toBe(false);
    // El handler falló → se libera el claim → el reintento de Stripe reprocesa.
    await releaseWebhookEvent(eventId);
    expect((await claimWebhookEvent(eventId, 'invoice.paid')).claimed).toBe(true);
  });
});
