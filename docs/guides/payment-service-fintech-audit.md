# Auditoría FinTech — `payment-service`

**Alcance:** webhook de Stripe, controladores de suscripción/pago, y degradación de
servicios (PDF y notificación biométrica). **Método:** revisión estática + smoke tests
(`node --check` + simulación del claim idempotente). No hubo ejecución contra Stripe/Supabase.

## Resumen ejecutivo

| # | Hallazgo | Archivo:línea | Severidad | Estado |
|---|---|---|---|---|
| F1 | Idempotencia de webhook **no atómica y débil** → doble procesamiento (suscripciones/pagos duplicados) en entregas concurrentes | `webhookController.js:168-182`, `subscriptionModel.isEventAlreadyProcessed` | **CRÍTICO** | Corregido |
| F2 | Llamadas de escritura a Stripe **sin `Idempotency-Key`** → doble clic crea customers/sesiones duplicados | `paymentController.js:177,185`, `subscriptionController.js:110` | Alto | Corregido |
| F3 | En error de handler el webhook respondía **200 en prod** → se perdía la activación de un pago legítimo (Stripe no reintenta) | `webhookController.js:216-237` | Alto | Corregido |
| F4 | `pdfService` podía **lanzar** con campos nulos/caracteres de control (`.substring`/`.toUpperCase` sobre null) | `pdfService.js:76,89,100` | Medio | Corregido |
| OK | Verificación de **firma** de Stripe | `webhookController.js:145-162` | — | Correcta |
| OK | PDF y notificación biométrica **aislados** de la transacción | `biometricNotificationService.js`, `webhookController.js:334` | — | Correcto |

**Parches entregados:** migración `006` + `subscriptionModel.js`, `webhookController.js`,
`paymentController.js`, `subscriptionController.js`, `pdfService.js`.

---

## Eje 1 — Webhook de Stripe

### Firma (correcta, sin riesgo de inyección de eventos falsos)
`handleStripeWebhook` verifica la firma nativa con
`stripe.webhooks.constructEvent(req.rawBody, signature, STRIPE_WEBHOOK_SECRET)`
(`webhookController.js:149-153`) sobre el **Buffer raw** (montado en `main.js` antes del
parser JSON) y responde **400** si falla (`:161`). El `STRIPE_WEBHOOK_SECRET` es obligatorio
y validado (`environment.js` exige prefijo `whsec_`). **No es posible inyectar un evento
`invoice.paid` simulado para activar una membresía sin pago**: sin la firma HMAC-SHA256
válida (que solo Stripe puede generar) el evento se rechaza. La tolerancia de 300 s de
`constructEvent` mitiga replays del propio webhook.

### F1 (Crítico) — Idempotencia no atómica → doble activación
El control anterior era una secuencia **check-then-act no atómica**:

```
webhookController.js:170  const alreadyProcessed = await subscriptionModel.isEventAlreadyProcessed(eventId);
...                       // (procesa)
subscriptionModel        // el eventId solo queda registrado como EFECTO del handler
                         // (columna suscripciones.stripe_event_id_ultimo)
```

Dos problemas:
1. **Race at-least-once:** Stripe puede entregar el mismo evento de forma concurrente. Ambas
   entregas leen `isEventAlreadyProcessed` → *false* (el id aún no se guardó) → **ambas
   procesan**. En `handleInvoicePaid` sin suscripción local (`:282-305`) esto ejecuta
   `subscriptionModel.create` **dos veces** → filas de suscripción duplicadas y doble
   sincronización biométrica.
2. **Store débil:** `isEventAlreadyProcessed` consulta `stripe_event_id_ultimo` (el "último
   evento" por fila), no un ledger de eventos. Un evento reprocesado cuyo id ya no es el
   "último" de su suscripción no se detecta como procesado.
3. **Fail-open:** si la verificación de idempotencia lanzaba, el código **procesaba igual**
   (`:176-182`).

**Fix:** ledger dedicado `webhook_events_procesados` (migración `006`, `event_id` = **PK**) +
`subscriptionModel.claimWebhookEvent()` que hace un **INSERT atómico** del `event_id` **antes**
de procesar. El primero gana; una entrega concurrente/duplicada choca con la PK (`23505`) y se
descarta con `200 already_processed`. Si el ledger no está disponible, se responde **503**
(fail-closed) para que Stripe reintente — nunca se procesa sin garantía de unicidad. Smoke test:
`claim("evt_123")` → `{claimed:true}`; segundo → `{claimed:false}`.

### F3 (Alto) — Pérdida de pagos en error de handler
El handler respondía **200 en producción** ante cualquier excepción (`:228-236`), con lo que
Stripe **no reintentaba** y una activación legítima podía perderse silenciosamente.
**Fix:** ante error se **libera el claim** (`releaseWebhookEvent`) y se responde **500**, de
modo que el reintento automático de Stripe reprocese el evento (ya idempotente).

---

## Eje 2 — Race conditions en suscripciones (doble clic)

### F2 (Alto) — Stripe sin `Idempotency-Key`
`createCheckoutSession` creaba customer y sesión **sin** clave de idempotencia
(`paymentController.js:177,185`), igual que `cancelAutoRenew`
(`subscriptionController.js:110`). Un doble clic o reintento de red generaba **customers de
Stripe duplicados** y múltiples sesiones de checkout (y potenciales cargos dobles si el usuario
completaba dos).

**Fix:** `Idempotency-Key` determinista en todas las escrituras a Stripe:
- customer: `gympro:customer:{userId}` (un usuario ⇒ un solo customer).
- checkout: `gympro:checkout:{userId}:{priceId}:{ventana30s}` (dobles clics rápidos colapsan
  en una sola sesión).
- cancelación: `gympro:cancel:{subId}:{día}`.

Stripe deduplica por esa clave durante 24 h y devuelve el objeto original en lugar de crear uno
nuevo. (El endpoint de recepción en efectivo, además, ya trae su propia `Idempotency-Key` desde
`cash_payment_client.js`.)

---

## Eje 3 — Degradación de servicio (fallback financiero)

**Diagnóstico: la arquitectura ya es correcta.** El PDF y la notificación biométrica están
**desacoplados** de la transacción de pago:

- `pdfService.generateReceiptPdf` **solo** se invoca en el endpoint de lectura
  `GET /:id/receipt` (`getReceiptPdf`), nunca en línea dentro del webhook ni del cobro. Un
  fallo de PDF (memoria, carácter extraño) devuelve 500 **solo en ese endpoint de recibo** —
  **no** afecta la activación de la membresía ni la transacción de Stripe.
- `biometricNotificationService` es **fire-and-forget** con `try/catch` interno y `timeout`
  de 5 s (`biometricNotificationService.js:65-73`); en el webhook se llama sin `await` y con
  `.catch` (`webhookController.js:334-339`). Un fallo de red del access-service **no** rompe el
  webhook; el pull de la terminal ZKTeco reintenta.

### F4 (Medio) — Endurecimiento del PDF
Aunque esté aislado, `pdfService` podía **lanzar** (no solo degradar) si un registro traía
campos nulos: `subscription.id.substring()` (`:76`), `subscription.usuario_id.substring()`
(`:89`), `subscription.estado.toUpperCase()` (`:100`). Un carácter de control (`\x00`, emoji)
en el nombre no lanzaba pero ensuciaba el render.
**Fix:** coerción segura (`clean()` que elimina control chars y acota longitud) y locales
`safeId`/`safeEstado`/`safeUserId` con defaults. Ahora un registro malformado produce un recibo
degradado pero **válido**, nunca una excepción.

---

## Archivos entregados

```
docs/database/schemas/migrations/006_webhook_events_procesados.sql   (F1)
services/payment-service/src/models/subscriptionModel.js            (F1: claim/release)
services/payment-service/src/controllers/webhookController.js       (F1, F3)
services/payment-service/src/controllers/paymentController.js       (F2)
services/payment-service/src/controllers/subscriptionController.js  (F2)
services/payment-service/src/services/pdfService.js                 (F4)
```

**Acción requerida en producción:** aplicar la migración `006`. Todos los archivos tocados
pasan `node --check` y el flujo de idempotencia se validó con un smoke test (claim único vs.
duplicado concurrente).

### Nota de comportamiento
El webhook ahora responde **500** ante un error de handler (antes 200 en prod). Es el
comportamiento FinTech-correcto: fuerza el reintento de Stripe para no perder activaciones. Un
evento genuinamente "envenenado" reintentará hasta 72 h y quedará logueado; conviene una alerta
sobre `webhook_events_procesados.resultado='error'` o sobre los logs de
`processing_error_will_retry`.
