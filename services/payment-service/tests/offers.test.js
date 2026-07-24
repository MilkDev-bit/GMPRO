/**
 * @file services/payment-service/tests/offers.test.js
 * @description Suite unitaria + integración del sistema de CUPONES/OFERTAS.
 *
 * Cubre los tres flujos nuevos, aislando BD (Supabase) y Stripe con jest.mock():
 *   Bloque 1 — Endpoints admin (CRUD + RBAC): 403 sin rol, 200/201 admin, 409 dup.
 *   Bloque 2 — Checkout (validación de cupón): 400 inválido/inactivo/expirado/
 *              no-vigente/agotado; 200 con inyección exacta de `discounts`.
 *   Bloque 3 — Webhook checkout.session.completed: canje → increment_offer_usage.
 *
 * NINGUNA llamada de red real: el cliente Supabase se aísla mockeando los modelos
 * (offerModel/subscriptionModel) y Stripe mockeando config/stripe.
 */

'use strict';

// ── Entorno ANTES de requerir cualquier módulo del servicio ───────────────────
// config/environment.js y packages_shared/jwtVerify hacen process.exit(1) si
// faltan/invalidan variables al cargarse. Se fijan aquí, en orden, antes de los
// require() de la app (las asignaciones NO se hoistean; los require() sí corren
// en su sitio, después de esto).
process.env.NODE_ENV                  = 'test';
process.env.PORT                      = '3003';
process.env.SUPABASE_URL              = 'https://test.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_' + 'x'.repeat(30);
process.env.SUPABASE_DB_SCHEMA        = 'payment_service_db';
process.env.JWT_SECRET                = 'a'.repeat(64); // >= 64 chars
process.env.JWT_ALGORITHM             = 'HS512';
process.env.STRIPE_SECRET_KEY         = 'sk_test_' + 'x'.repeat(24);
process.env.STRIPE_WEBHOOK_SECRET     = 'whsec_' + 'x'.repeat(24);
process.env.STRIPE_DEFAULT_CURRENCY   = 'usd';
process.env.CASH_PAYMENT_API_KEY      = 'k'.repeat(32);
process.env.INTER_SERVICE_SECRET      = 's'.repeat(32);
process.env.CORS_ALLOWED_ORIGINS      = 'http://localhost:5173';

const express   = require('express');
const request   = require('supertest');
const jwt       = require('jsonwebtoken');

// ── Aislamiento de BD y Stripe ────────────────────────────────────────────────
jest.mock('../src/models/offerModel');
jest.mock('../src/models/subscriptionModel');
jest.mock('../src/services/biometricNotificationService', () => ({
  notifyBiometricSync:   jest.fn(),
  notifyBiometricDelete: jest.fn(),
}));

// Cliente Stripe mockeado (prefijo `mock` → permitido en la factory hoisteada).
const mockStripe = {
  customers: { create: jest.fn() },
  coupons:   { retrieve: jest.fn(), create: jest.fn() },
  checkout:  { sessions: { create: jest.fn() } },
  webhooks:  { constructEvent: jest.fn() },
};
jest.mock('../src/config/stripe', () => ({
  getStripeClient:    () => mockStripe,
  STRIPE_API_VERSION: 'test',
}));

// Módulos bajo prueba (ya con los mocks aplicados).
const offerModel         = require('../src/models/offerModel');
const subscriptionModel  = require('../src/models/subscriptionModel');
const createAdminRoutes  = require('../src/routes/adminRoutes');
const paymentRoutes      = require('../src/routes/paymentRoutes');
const { handleStripeWebhook } = require('../src/controllers/webhookController');

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Firma un JWT válido (mismo secret/alg que jwtVerify) con el rol indicado. */
function signToken(role) {
  return jwt.sign(
    { sub: 'user-123', jti: 'jti-123', role, email: 'u@test.com' },
    process.env.JWT_SECRET,
    { algorithm: 'HS512' },
  );
}

/** App que monta las rutas admin con RBAC real (redis null → sin blacklist). */
function buildAdminApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin', createAdminRoutes({ redisClient: null }));
  return app;
}

/** App de checkout: inyecta req.user (la auth se prueba en el Bloque 1). */
function buildCheckoutApp() {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.user = { id: 'user-123', email: 'u@test.com' }; next(); });
  app.use('/api/v1/payments', paymentRoutes);
  return app;
}

/** res mock mínimo para invocar handlers directamente. */
function makeRes() {
  const res = { statusCode: null, body: null };
  res.status = jest.fn((c) => { res.statusCode = c; return res; });
  res.json   = jest.fn((b) => { res.body = b; return res; });
  return res;
}

/** Oferta base válida (fechas vigentes, con cupo). */
function validOffer(overrides = {}) {
  return {
    id:           'offer-1',
    nombre:       'Verano 25%',
    codigo:       'SUMMER25',
    tipo:         'porcentaje',
    valor:        25,
    activa:       true,
    valido_desde: new Date(Date.now() - 86_400_000).toISOString(), // ayer
    valido_hasta: new Date(Date.now() + 86_400_000).toISOString(), // mañana
    usos:         0,
    max_usos:     100,
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
});

// ══════════════════════════════════════════════════════════════════════════════
// BLOQUE 1 — Endpoints Admin (CRUD + RBAC)
// ══════════════════════════════════════════════════════════════════════════════
describe('Bloque 1 · Admin /api/v1/admin/offers (RBAC + CRUD)', () => {
  const app = buildAdminApp();

  const validBody = {
    nombre:       'Black Friday',
    codigo:       'BF-2026',
    tipo:         'porcentaje',
    valor:        30,
    valido_desde: '2026-11-01T00:00:00.000Z',
    valido_hasta: '2026-11-30T23:59:59.000Z',
    max_usos:     500,
  };

  test('401 si no se envía token', async () => {
    const res = await request(app).get('/api/v1/admin/offers');
    expect(res.status).toBe(401);
  });

  test('403 si el rol NO está en STAFF_ROLES (GET)', async () => {
    const res = await request(app)
      .get('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('miembro')}`);
    expect(res.status).toBe(403);
    expect(offerModel.listOffers).not.toHaveBeenCalled();
  });

  test('403 si el rol NO está en STAFF_ROLES (POST)', async () => {
    const res = await request(app)
      .post('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('miembro')}`)
      .send(validBody);
    expect(res.status).toBe(403);
    expect(offerModel.createOffer).not.toHaveBeenCalled();
  });

  test('403 si el rol NO está en STAFF_ROLES (PATCH)', async () => {
    const res = await request(app)
      .patch('/api/v1/admin/offers/11111111-1111-4111-8111-111111111111')
      .set('Authorization', `Bearer ${signToken('miembro')}`)
      .send({ activa: false });
    expect(res.status).toBe(403);
    expect(offerModel.setActive).not.toHaveBeenCalled();
  });

  test('200 lista ofertas para un admin', async () => {
    const offers = [validOffer(), validOffer({ id: 'offer-2', codigo: 'WINTER10' })];
    offerModel.listOffers.mockResolvedValue(offers);

    const res = await request(app)
      .get('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('admin')}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(offerModel.listOffers).toHaveBeenCalledTimes(1);
  });

  test('200 también para el rol staff (no solo admin)', async () => {
    offerModel.listOffers.mockResolvedValue([]);
    const res = await request(app)
      .get('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('staff')}`);
    expect(res.status).toBe(200);
  });

  test('201 crea una oferta (admin)', async () => {
    const created = validOffer({ codigo: 'BF-2026', nombre: 'Black Friday', valor: 30 });
    offerModel.createOffer.mockResolvedValue(created);

    const res = await request(app)
      .post('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send(validBody);

    expect(res.status).toBe(201);
    expect(res.body.data.codigo).toBe('BF-2026');
    expect(offerModel.createOffer).toHaveBeenCalledWith(
      expect.objectContaining({ codigo: 'BF-2026', tipo: 'porcentaje', valor: 30 }),
    );
  });

  test('422 si el body de creación es inválido (código con caracteres no permitidos)', async () => {
    const res = await request(app)
      .post('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send({ ...validBody, codigo: 'bad code!!' });
    expect(res.status).toBe(422);
    expect(offerModel.createOffer).not.toHaveBeenCalled();
  });

  test('409 si el código ya existe (error 23505 de Postgres)', async () => {
    const dup = Object.assign(new Error('duplicate key'), { code: '23505' });
    offerModel.createOffer.mockRejectedValue(dup);

    const res = await request(app)
      .post('/api/v1/admin/offers')
      .set('Authorization', `Bearer ${signToken('admin')}`)
      .send(validBody);

    expect(res.status).toBe(409);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toMatch(/código/i);
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// BLOQUE 2 — Checkout (validación de cupones + mapeo a Stripe)
// ══════════════════════════════════════════════════════════════════════════════
describe('Bloque 2 · POST /api/v1/payments/create-checkout-session (cupones)', () => {
  const app = buildCheckoutApp();

  beforeEach(() => {
    // Camino "feliz" de infraestructura Stripe/BD ajeno al cupón.
    subscriptionModel.getHistoryByUserId.mockResolvedValue([]);
    mockStripe.customers.create.mockResolvedValue({ id: 'cus_test' });
    mockStripe.checkout.sessions.create.mockResolvedValue({ id: 'cs_test', url: 'https://stripe.test/cs_test' });
  });

  function post(body) {
    return request(app).post('/api/v1/payments/create-checkout-session').send(body);
  }

  // ── 400: ofertas inválidas ───────────────────────────────────────────────
  test('400 si el offerCode NO existe', async () => {
    offerModel.findByCodigo.mockResolvedValue(null);
    const res = await post({ priceId: 'price_1', offerCode: 'NOEXISTE' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/no existe/i);
    expect(mockStripe.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test('400 si la oferta está inactiva', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer({ activa: false }));
    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/activo/i);
    expect(mockStripe.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test('400 si la oferta aún no está vigente (valido_desde futuro)', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer({
      valido_desde: new Date(Date.now() + 86_400_000).toISOString(),
    }));
    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/vigente/i);
  });

  test('400 si la oferta expiró (valido_hasta pasado)', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer({
      valido_desde: new Date(Date.now() - 172_800_000).toISOString(),
      valido_hasta: new Date(Date.now() - 86_400_000).toISOString(),
    }));
    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/expirado/i);
  });

  test('400 si la oferta está agotada (usos >= max_usos)', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer({ usos: 100, max_usos: 100 }));
    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/límite de usos/i);
    expect(mockStripe.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test('422 si el offerCode viola el formato (validación de ruta)', async () => {
    const res = await post({ priceId: 'price_1', offerCode: 'a b!' });
    expect(res.status).toBe(422);
    expect(offerModel.findByCodigo).not.toHaveBeenCalled();
  });

  // ── 200: mapeo a Stripe y aserciones estrictas del descuento ──────────────
  test('200 crea cupón "al vuelo" e inyecta discounts EXACTOS (porcentaje)', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer()); // SUMMER25, 25%
    mockStripe.coupons.retrieve.mockRejectedValue({ statusCode: 404, code: 'resource_missing' });
    mockStripe.coupons.create.mockResolvedValue({ id: 'SUMMER25' });

    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });

    expect(res.status).toBe(200);
    expect(res.body.data.sessionId).toBe('cs_test');

    // El cupón se crea con el mapeo correcto (id == código, percent_off).
    expect(mockStripe.coupons.create).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'SUMMER25', percent_off: 25, duration: 'once' }),
      expect.objectContaining({ idempotencyKey: expect.stringContaining('SUMMER25') }),
    );

    // Aserción ESTRICTA del descuento inyectado en la sesión de Stripe.
    expect(mockStripe.checkout.sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({
        discounts: [{ coupon: 'SUMMER25' }],
        metadata:  expect.objectContaining({ offer_code: 'SUMMER25' }),
      }),
      expect.objectContaining({ idempotencyKey: expect.stringContaining('SUMMER25') }),
    );
  });

  test('200 reutiliza el cupón existente (retrieve OK → NO se crea)', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer());
    mockStripe.coupons.retrieve.mockResolvedValue({ id: 'SUMMER25' });

    const res = await post({ priceId: 'price_1', offerCode: 'SUMMER25' });

    expect(res.status).toBe(200);
    expect(mockStripe.coupons.create).not.toHaveBeenCalled();
    const [params] = mockStripe.checkout.sessions.create.mock.calls[0];
    expect(params.discounts).toEqual([{ coupon: 'SUMMER25' }]);
  });

  test('200 mapea monto_fijo → amount_off en centavos + currency', async () => {
    offerModel.findByCodigo.mockResolvedValue(validOffer({
      codigo: 'FLAT10', tipo: 'monto_fijo', valor: 10,
    }));
    mockStripe.coupons.retrieve.mockRejectedValue({ statusCode: 404, code: 'resource_missing' });
    mockStripe.coupons.create.mockResolvedValue({ id: 'FLAT10' });

    const res = await post({ priceId: 'price_1', offerCode: 'FLAT10' });

    expect(res.status).toBe(200);
    expect(mockStripe.coupons.create).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'FLAT10', amount_off: 1000, currency: 'usd', duration: 'once' }),
      expect.any(Object),
    );
  });

  test('200 SIN offerCode: no consulta ofertas ni inyecta discounts', async () => {
    const res = await post({ priceId: 'price_1' });

    expect(res.status).toBe(200);
    expect(offerModel.findByCodigo).not.toHaveBeenCalled();
    expect(mockStripe.coupons.create).not.toHaveBeenCalled();
    const [params] = mockStripe.checkout.sessions.create.mock.calls[0];
    expect(params.discounts).toBeUndefined();
    expect(params.metadata.offer_code).toBeUndefined();
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// BLOQUE 3 — Webhook checkout.session.completed (incremento atómico)
// ══════════════════════════════════════════════════════════════════════════════
describe('Bloque 3 · Webhook checkout.session.completed (canje)', () => {
  beforeEach(() => {
    // Firma válida (bypass) + claim de idempotencia concedido.
    subscriptionModel.claimWebhookEvent.mockResolvedValue({ claimed: true });
    subscriptionModel.releaseWebhookEvent.mockResolvedValue(undefined);
  });

  function invoke(event) {
    mockStripe.webhooks.constructEvent.mockReturnValue(event);
    const req = { headers: { 'stripe-signature': 'sig_test' }, rawBody: Buffer.from('{}') };
    const res = makeRes();
    return handleStripeWebhook(req, res).then(() => res);
  }

  test('con metadata.offer_code → invoca increment_offer_usage y responde 200', async () => {
    offerModel.incrementOfferUsage.mockResolvedValue(5);
    const event = {
      id: 'evt_1', type: 'checkout.session.completed',
      data: { object: { id: 'cs_1', metadata: { offer_code: 'SUMMER25' } } },
    };

    const res = await invoke(event);

    expect(offerModel.incrementOfferUsage).toHaveBeenCalledWith('SUMMER25');
    expect(offerModel.incrementOfferUsage).toHaveBeenCalledTimes(1);
    expect(res.statusCode).toBe(200);
  });

  test('SIN offer_code (checkout sin cupón) → NO incrementa, responde 200', async () => {
    const event = {
      id: 'evt_2', type: 'checkout.session.completed',
      data: { object: { id: 'cs_2', metadata: {} } },
    };

    const res = await invoke(event);

    expect(offerModel.incrementOfferUsage).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
  });

  test('evento duplicado (claim no concedido) → NO despacha el handler', async () => {
    subscriptionModel.claimWebhookEvent.mockResolvedValue({ claimed: false });
    const event = {
      id: 'evt_1', type: 'checkout.session.completed',
      data: { object: { id: 'cs_1', metadata: { offer_code: 'SUMMER25' } } },
    };

    const res = await invoke(event);

    expect(offerModel.incrementOfferUsage).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual(expect.objectContaining({ status: 'already_processed' }));
  });

  test('código inexistente al canjear (RPC devuelve null) → 200 sin lanzar', async () => {
    offerModel.incrementOfferUsage.mockResolvedValue(null);
    const event = {
      id: 'evt_3', type: 'checkout.session.completed',
      data: { object: { id: 'cs_3', metadata: { offer_code: 'GHOST' } } },
    };

    const res = await invoke(event);

    expect(offerModel.incrementOfferUsage).toHaveBeenCalledWith('GHOST');
    expect(res.statusCode).toBe(200);
  });
});
