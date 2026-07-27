# Audit 04 — Seguridad de API (OWASP API Security Top 10:2023)

> Alcance: los 5 microservicios REST (`services/*`) que exponen `/api/v1/*`.
> Basado en `audit-00-mapeo.md`. Fecha: 2026-07-24. Método: revisión estática con
> evidencia `archivo:línea`. Los ítems ya cubiertos en `audit-01/02/03` se
> **recitan con referencia cruzada**; se profundiza en los específicos de API
> (mass assignment, over-fetching, inventario, consumo de recursos).

## ¿Expone APIs?
**Sí.** Cinco APIs REST Express montadas bajo `/api/v1/*` (auth 3001, access 3002,
payment 3003, fitness 3004, ai 3005). **No hay GraphQL** (grep `graphql/apollo` = 0),
por lo que los ítems de introspección/consultas anidadas no aplican. Se procede.

## Tabla resumen

| API# | Categoría | Hallazgo | Severidad | Evidencia |
|------|-----------|----------|-----------|-----------|
| API1 | BOLA / IDOR (objeto) | Autorización a nivel de objeto correcta (ownership) | ✅ Correcto | `paymentController` getReceiptPdf; `routineController.js:71` |
| API2 | Autenticación rota | Sesión/JWT/MFA robustos | ✅ Correcto | ver `audit-03` A07 |
| API3 | Propiedad de objeto (mass assignment / over-fetching) | Sin mass assignment; **over-fetching por `select('*')` inconsistente** | Media | `fitness/models/*`; `accessModel`; `paymentHistoryModel.js:79` |
| API4 | Consumo de recursos | Paginación clamped + payload limitado + rate limiting en capas | ✅ Correcto (residual: A10-1) | `exerciseModel.js:34`; `main.js` maxPayloadSize |
| API5 | Autorización de función (BFLA) | RBAC + API Key + M2M por endpoint | ✅ Correcto | `access/main.js:116-121`; `admin` routes |
| API6 | Flujos de negocio sensibles | Checkout con idempotencia + límite de cupón atómico | ✅ Correcto | ver fases previas |
| API7 | SSRF | Guard sin cablear; ninguna URL de usuario llega a fetch | Baja (latente) | ver `audit-01` A01-3 |
| API8 | Misconfiguración | CORS explícito; `.dockerignore` mal ubicado | Media | ver `audit-01` A02-1 |
| API9 | **Gestión de inventario** | Rutas **sin versión duplicadas** + sin spec OpenAPI | Media–Baja | `access/main.js:110-121`; `payment/main.js:109-114` |
| API10 | Consumo de APIs de terceros | Llamadas salientes con timeout y normalización | ✅ Correcto | `llmClientService.js:217`; `foodReconciliationService.js` |

---

## API1 — BOLA / IDOR (autorización a nivel de objeto) · ✅ Correcto (Baja)
Los accesos por `:id` verifican pertenencia:
- Recibos: `getReceiptPdf` → `req.user.id !== subscription.usuario_id && role !== 'admin'` → 403.
- Rutinas: `routineModel.deleteRoutine(id, usuarioId)` (borrado scoped por `usuario_id`, `routineController.js:71`).
- Progreso: consultas siempre `.eq('usuario_id', usuarioId)` (`progressModel.js`).
Detalle y evidencia completa en `audit-01` (A01-1/A01-2). No se hallaron IDOR en los
endpoints revisados. **Pendiente:** inventario exhaustivo de rutas de los 5 servicios
para confirmar el patrón en cada `GET/PUT/DELETE /:id` de access/ai.

## API2 — Autenticación rota · ✅ Correcto
Rotación de refresh con reuse-detection, cookies `httpOnly/secure/strict`, WebAuthn
con challenge single-use, recuperación anti-enumeración. Detalle en `audit-03` (A07).

## API3 — Autorización a nivel de propiedad de objeto · Severidad: Media

### Mass assignment — ✅ Correcto
No se interpola `req.body` directo en escrituras: **no hay** `insert(req.body)`,
`update(req.body)` ni `{ ...req.body }` (grep = 0). Todos los modelos construyen el
objeto con **campos explícitos** (`userModel.js:112`, `routineModel.js`,
`offerModel.js`, `accessModel.js:69/106`, etc.). Aunque un cliente envíe campos
extra (p. ej. `rol:'admin'`, `activo:true`), el modelo solo persiste los nombrados →
mass assignment mitigado por diseño.

### Over-fetching / exposición excesiva — Media
Uso **inconsistente** de `select('*')` en respuestas devueltas al cliente:
- `fitness`: `routineModel.js:64`, `progressModel.js:24,70,94-95`, `exerciseModel.js:56`.
- `access`: `accessModel.js:77,115,138,211`.
- `payment`: `paymentHistoryModel.js:79` (asiento devuelto tras cobro en recepción,
  incluye `receptionist_id`, `notas`), `paymentController.js:369` (uso server-side para PDF).

Contraste: auth y el core de payment usan **listas `SAFE_COLUMNS`** explícitas
(`userModel.js:19`, `subscriptionModel.js:19`), que es el patrón correcto.
- **Impacto:** medio. Hoy son datos del propio usuario u operativos, pero `select('*')`
  es frágil: al añadir una columna sensible (PII, flags internos) se expone
  automáticamente en la respuesta sin que nadie lo note.
- **Remediación:** sustituir `select('*')` por listas de columnas explícitas
  (patrón `SAFE_COLUMNS`) en fitness/access y en el retorno de `paymentHistoryModel`;
  no confiar en que el cliente filtre.

## API4 — Consumo descontrolado de recursos · ✅ Correcto (residual A10-1)
- **Paginación acotada:** `exerciseModel.js:34`
  `sizeNum = Math.min(env.MAX_PAGE_SIZE, Math.max(1, parseInt(pageSize)||DEFAULT))`;
  listados admin con `Math.min(limit, 200|500)` (`userModel.js:444`,
  `subscriptionModel.js:430`, `offerModel.js:20`). Sin listados no acotados devueltos
  al cliente.
- **Tamaño de payload explícito por servicio:** 10kb (access/payment), 20kb (ai),
  50kb (auth/fitness), 1mb solo para el webhook de Stripe (`*/main.js`).
- **Rate limiting en capas:** global/IP + por-usuario + por-cuenta en `/login` +
  específicos (QR, ticket, pagos). Ver `audit-03`.
- **Residual:** el rate limiter degrada a MemoryStore por proceso si falta Redis
  (**fail-open entre réplicas**) — ver `audit-03` **A10-1** (remediar a fail-closed
  en limitadores de auth).

## API5 — Autorización a nivel de función (BFLA) · ✅ Correcto
Cada función privilegiada exige su control:
- `/api/v1/*/admin/*` → `createJwtVerifyMiddleware({ requiredRoles: STAFF_ROLES })`.
- `create-ticket` → `staffOnlyVerify` (RBAC) (`access/main.js:116`).
- `validate-ticket` → `requireTurnstileApiKey` (hardware) (`:120`).
- `cash-payment` → `requireApiKey` (recepción) (`payment/main.js:109`).
- `/internal` → M2M `requireInterServiceSecret`/`createInterServiceAuthMiddleware`
  (timing-safe). No se detectaron funciones sensibles sin control.

## API6 — Acceso a flujos de negocio sensibles · ✅ Correcto
Checkout/pagos: idempotencia atómica (Idempotency-Key en Stripe + claim de webhook
por PK), rate limit de pagos (10/min), y canje de cupón con incremento **atómico** y
tope `max_usos`. Mitiga abuso automatizado del flujo de compra.

## API7 — SSRF · Baja (latente)
`ssrfGuard` completo pero **solo usado en tests**; ninguna URL provista por el
usuario llega a un `fetch` server-side (barcodes saneados, resto de destinos fijos/
internos). Detalle en `audit-01` (A01-3) y `audit-02` (A05). Cablear el guard si se
añade fetch de URL de usuario.

## API8 — Configuración insegura (incl. CORS) · Media
- **CORS correcto:** lista explícita de orígenes, nunca `*` con `credentials`
  (`corsConfig.js:126-150`). Nota: permite requests **sin** header `Origin` (clientes
  no-browser) — aceptable y documentado.
- **`.dockerignore` mal ubicado** (secretos en capa builder) — ver `audit-01` **A02-1**.
- Helmet/HSTS/errorHandler correctos — ver `audit-01/02`.

## API9 — Gestión incorrecta de inventario · Severidad: Media–Baja

### Rutas sin versión duplicadas (mayor superficie / deprecación difícil)
`access-service` monta **cada endpoint dos veces**, con y sin prefijo de versión:
- `/generate-qr` **y** `/api/v1/generate-qr` (`access/main.js:110-111`).
- `/create-ticket` **y** `/api/v1/create-ticket` (`:116-117`).
- `/validate-ticket` **y** `/api/v1/validate-ticket` (`:120-121`).
`payment-service` duplica `/api/v1/cash-payment` y `/api/v1/payments/cash-payment`
(`payment/main.js:109-114`).
- **Impacto:** medio-bajo. Las variantes comparten el **mismo middleware** (no son
  shadow APIs con auth más débil), pero **duplican la superficie**, complican el
  versionado/deprecación y el monitoreo, y aumentan el riesgo de que un cambio de
  seguridad se aplique a una variante y no a la otra.
- **Remediación:** consolidar a la ruta **versionada** (`/api/v1/...`), marcar las
  no versionadas como deprecadas (redirect/410 con fecha de retiro) y actualizar los
  clientes (torniquete/recepción). Añadir un test que falle si se registra una ruta
  fuera de `/api/v1`.

### Sin especificación de API (OpenAPI/Swagger)
No existe un contrato OpenAPI/Swagger en el repo (búsqueda = 0). Sin inventario
formal, es difícil detectar shadow endpoints y auditar cobertura de auth.
- **Remediación:** mantener un `openapi.yaml` por servicio (o generado) como fuente
  de verdad del inventario; integrarlo al CI para detectar drift.

### Endpoints de salud sin auth
`/health` es público en los 5 servicios (esperado para Railway). Exponen
`service`, `status`, `uptime` — divulgación mínima; aceptable.

## API10 — Consumo inseguro de APIs de terceros · ✅ Correcto
Las llamadas salientes (Stripe SDK, LLM APIs, Open Food Facts, servicios internos)
usan **timeouts** (`AbortController`/`signal`, `llmClientService.js:217`; axios 5s),
**sanean** los datos que construyen la URL (barcode → solo dígitos) y **normalizan**
la respuesta del tercero antes de usarla (`foodReconciliationService.js`), sin confiar
ciegamente en su estructura. No hay reenvío de URLs de terceros controladas por el
usuario.

---

## Priorización de remediación (específica de API)

| Prioridad | Acción | Ítem |
|-----------|--------|------|
| 1 | Reemplazar `select('*')` por columnas explícitas en fitness/access/paymentHistory | API3 (over-fetching) |
| 2 | Consolidar rutas a `/api/v1` + deprecar las no versionadas; test anti-drift | API9 |
| 3 | Rate limiters de auth **fail-closed** (no MemoryStore silencioso) | API4 / A10-1 |
| 4 | Publicar OpenAPI por servicio como inventario formal | API9 |
| 5 | Cablear `ssrfGuard` si se añade fetch de URL de usuario | API7 |

> Balance: la postura de API es **sólida** en los riesgos de mayor impacto (BOLA,
> BFLA, autenticación, mass assignment, consumo de recursos). Las mejoras
> accionables son de **higiene**: disciplina de columnas en respuestas (evitar
> `select('*')`), consolidación del inventario de rutas y el fail-closed del rate
> limiter (compartido con `audit-03`).
