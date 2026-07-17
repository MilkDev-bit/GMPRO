# Tarea 3.4 — Flujo de Pago Presencial y Activación de Acceso Inmediato

Arquitectura de extremo a extremo para cuando un socio paga su membresía en el
mostrador (efectivo o terminal física). El objetivo es que la activación impacte
**en tiempo real** en tres superficies: la base de datos (Supabase), el torniquete
físico y la app móvil del socio — sin fricción ni reinicios de la app.

## 1. Componentes y responsabilidades

| Componente | Ubicación | Rol en el flujo |
|---|---|---|
| Panel de mostrador | `reception-hardware-controller/node` | El staff registra el cobro; llama al controlador local |
| Controlador local | `node/cash_payment_client.js` | Dispara el cobro a Railway con API Key, imprime ticket, encola offline |
| Impresora térmica | `node/reception_controller.js` | Imprime ticket + QR de cortesía (cola sorda si falla) |
| `payment-service` | Railway | Registra `historial_pagos`, crea/renueva `suscripciones`, orquesta sincronía |
| `access-service` | Railway | Invalida caché de vigencia y acuña el pase de cortesía del día |
| Supabase (PostgreSQL) | — | Fuente de verdad + canal Realtime hacia la app |
| App móvil (Flutter) | `features/subscription` | Escucha Realtime y quita el overlay de bloqueo al instante |

## 2. Modelo de datos

**`payment_service_db.historial_pagos`** (nuevo — migración `004`): ledger
**inmutable** de cada transacción presencial. Un asiento por cobro; las
correcciones se hacen con asientos inversos (`estado_pago` `refunded`/`voided`).
Campos clave: `usuario_id`, `suscripcion_id`, `monto`, `metodo_pago`
(`cash`/`card_terminal`/`transfer`), `periodo_desde/hasta`, `numero_recibo`
(folio impreso), `pase_cortesia_codigo`, `receptionist_id` (trazabilidad OWASP A09).

**`payment_service_db.suscripciones`**: fuente de verdad de vigencia. El pago en
efectivo **crea o extiende** un registro manual con `estado = 'active'`,
`metodo_pago = 'cash'` y `valido_hasta` recalculado (si ya había vigencia, se
extiende desde `valido_hasta`, no desde hoy, para no perder días).

**`access_service_db.tickets_visitas`**: el pase de cortesía del día es un ticket
de un solo uso (`estado = 'active'`, `expira_en` = fin del día), validable en el
torniquete por el flujo `validate-ticket` existente.

> Convención de valores en **inglés** (`active`, `cash`, `completed`) por
> coherencia con los modelos JS en ejecución y `access-service/paymentClientService`.
> La migración `004` crea una tabla autoconsistente, sin depender de los ENUM heredados.

## 3. Flujo de endpoints (camino feliz)

```
[Panel mostrador]
    │ POST http://127.0.0.1:18999/register-cash-payment
    │ { usuario_id, monto, plan_duracion_dias, metodo_pago }
    ▼
[reception: cash_payment_client.js]
    │ POST /api/v1/payments/cash-payment   (header x-api-key)     ── Railway ──►
    ▼
[payment-service: paymentController.registerCashPayment]
    │ 1. subscriptionModel.registerCashPayment()  → suscripciones estado 'active'
    │ 2. accessSyncService.mintCourtesyPass()      → access-service acuña ticket del día
    │ 3. paymentHistoryModel.recordCashPayment()   → asiento en historial_pagos
    │ 4. accessSyncService.invalidateMembershipCache() → borra/pre-calienta Redis
    │ 5. responde { numero_recibo, pase_cortesia, ticket_impresion, valido_hasta }
    ▼
[reception] imprime ticket_impresion (recibo + QR de cortesía)
    │
    ├─► [Torniquete] al escanear el QR de cortesía → access-service /validate-ticket → abre
    └─► [Supabase] UPDATE en suscripciones → Realtime → app quita overlay al instante
```

### 3.1 Sincronización inmediata en el torniquete

`access-service` cachea la vigencia en Redis (`access:membership_status:{id}`,
TTL 60s). Sin invalidación, un socio recién pagado seguiría viendo *"vencido"*
hasta 60s. Por eso `payment-service` llama al endpoint interno
`POST /api/v1/access/internal/invalidate-membership-cache` (autenticado con
`INTER_SERVICE_SECRET`), que **borra** la clave y la **pre-calienta** con el
estado vigente → el primer escaneo posterior es instantáneo (<5 ms).

### 3.2 Ticket físico y QR de cortesía

La respuesta incluye `ticket_impresion`, un payload listo para la impresora
térmica (`printDailyTicket`): nombre del socio, folio de recibo, monto,
`valido_hasta` y el `codigo_ticket`/`qr_string` del pase de cortesía válido **ese
único día**. Así el socio entra hoy aunque su móvil aún no haya sincronizado.

### 3.3 Reactividad en la app (Flutter Realtime)

`subscription_provider.dart` abre un canal Supabase Realtime
(`SubscriptionRealtimeService`) sobre `payment_service_db.suscripciones` filtrado
por `usuario_id`. Cuando el `estado` pasa de `past_due`/`inactive` a `active`,
Supabase emite el evento `UPDATE`, el provider actualiza su estado y
`isAccessValidProvider` se vuelve `true` — los overlays blurreados de
`nutrition_main_screen.dart` y `workout_main_screen.dart` desaparecen **sin
cerrar ni reabrir la app**. El polling HTTP queda como carga inicial y respaldo.

**Requisitos Supabase:** publicar el esquema en `supabase_realtime`
(`ALTER PUBLICATION supabase_realtime ADD TABLE payment_service_db.suscripciones;`)
y una RLS que permita al socio leer **solo su propia fila**. Inicializar en
`main.dart`: `await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);`
(claves vía `--dart-define`).

## 4. Manejo de excepciones

| Escenario | Comportamiento | Dónde |
|---|---|---|
| **Red local / Railway caídos al cobrar** | El pago se **encola** en `pending_cash_payments.jsonl` con clave de idempotencia; se responde `200 encolado_offline`; el Auto-Healer reintenta con backoff al volver la línea. No se pierde ni bloquea la caja. | `cash_payment_client.js` |
| **Error 4xx (validación / API Key)** | **No** se encola (reintentar no ayuda); se informa al staff para corregir. | `cash_payment_client.js` |
| **`access-service` caído** (cortesía/caché) | Best-effort con timeout 2.5s; el pago **igual se confirma**. La vigencia sigue disponible por el fallback a DB de `access-service`. Se registra la degradación. | `accessSyncService.js` |
| **Impresora sin papel / apagada** | El ticket se guarda en `failed_tickets.jsonl` (cola sorda) y se reimprime al reconectar; nunca devuelve 500. | `reception_controller.js` |
| **Cobro doble por reintento** | `Idempotency-Key` estable por venta evita duplicados en la cola offline. | `cash_payment_client.js` |
| **Ledger** | `historial_pagos` es inmutable (trigger bloquea UPDATE/DELETE); correcciones vía asiento inverso. | migración `004` |

## 5. Variables de entorno nuevas

**payment-service**
```
ACCESS_SERVICE_INTERNAL_URL=http://access-service.railway.internal:3002/api/v1/access/internal
INTER_SERVICE_TIMEOUT_MS=2500
# (ya existentes) CASH_PAYMENT_API_KEY, INTER_SERVICE_SECRET
```

**access-service**: reutiliza `INTER_SERVICE_SECRET` y `REDIS_URL` existentes.

**reception-hardware-controller (node)**
```
PAYMENT_SERVICE_URL=https://payment-service.up.railway.app
CASH_PAYMENT_API_KEY=gympro_cash_rec01_xxxxxxxx   # misma que valida payment-service
CASH_REQUEST_TIMEOUT_MS=6000
```

**app móvil**: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

## 6. Archivos entregados

- `docs/database/schemas/migrations/004_add_historial_pagos_and_courtesy.sql`
- `services/access-service/src/middlewares/interServiceAuth.js`
- `services/access-service/src/controllers/internalController.js`
- `services/access-service/src/routes/internalRoutes.js` (+ wiring en `main.js`)
- `services/payment-service/src/services/accessSyncService.js`
- `services/payment-service/src/models/paymentHistoryModel.js`
- `services/payment-service/src/controllers/paymentController.js` (orquestación)
- `services/reception-hardware-controller/node/cash_payment_client.js` (+ wiring)
- `apps/gym_mobile_app/lib/features/subscription/data/datasources/subscription_realtime_service.dart`
- `apps/gym_mobile_app/lib/features/subscription/presentation/providers/subscription_provider.dart`
