# Auditoría de ciberseguridad IoT — `access-service` ↔ `reception-hardware-controller`

**Alcance:** lógica, endpoints y controladores de `access-service` y el puente serie/HTTP
con `reception-hardware-controller`. **Método:** revisión estática + pruebas de lógica
(`node --check` + smoke tests). No hubo ejecución contra Railway/Supabase/hardware real.

## Resumen ejecutivo

| # | Hallazgo | Archivo:línea | Severidad | Estado |
|---|---|---|---|---|
| C1 | Endpoints ADMS `/iclock/*` **sin autenticación**: exfiltración de plantillas biométricas, inyección de accesos y spoofing de comandos | `zkAdmsRoutes.js:32-42`, `zkAdmsController.js:22-126` | **CRÍTICO** | Corregido |
| C2 | Verificación de QR **no atómica** → replay / doble entrada concurrente dentro de los 30 s | `qrController.js:156-200`, `accessModel.js:isNonceAlreadyUsed` | **CRÍTICO** | Corregido |
| A1 | `PIN_CACHE` (Map) crece sin límite → **memory leak** en Railway | `zkAdmsService.js:26` | Alto | Corregido |
| A2 | Bloqueo permanente del relé: `isRelayBusy` puede quedar atascado en `true`; puertos serie liberados sin cerrar (fuga de fd/listeners) | `reception_controller.js` (triggerTurnstileUnlock + handlers) | Alto | Corregido |
| A3 | `generateCommandId` con colisiones (timestamp+random) → confirma comando equivocado | `zkAdmsService.js:90-92` | Medio | Corregido |
| M1 | Secretos hardcodeados como fallback en el controlador de recepción | `reception_controller.js:29`, `cash_payment_client.js` | Medio | Señalado |
| M2 | ADMS `Encrypt=0` y clave de torniquete única sin rotación | `zkAdmsController.js:121`, `turnstileAuth.js` | Bajo/Medio | Señalado |

**`turnstileAuth.js` (Eje 3): correcto.** Usa `timingSafeEqual` contra `TURNSTILE_API_KEY`
(env obligatoria, ≥32 chars, validada en `environment.js:21`). **No hay stubs ni bypass.**
El único riesgo asociado es el secreto por defecto hardcodeado del lado cliente (M1).

---

## Eje 1 — Falsificación y replay de QRs

### Criptografía (correcta)
`cryptoService.js` usa **AES-256-GCM** con IV aleatorio de 12 bytes y Auth Tag de 16
(`cryptoService.js:33-69`). Esto da confidencialidad **e integridad autenticada**: sin la
clave (`AES_ENCRYPTION_KEY`, 64 hex validados en `environment.js:43`) no se puede forjar ni
alterar un token — `decipher.final()` lanza ante cualquier bit modificado
(`cryptoService.js:109`). Equivale o supera a un HMAC-SHA256 para este propósito. El
`timestamp` lo pone el servidor (`qrController.js:55`), no el cliente, así que la ventana de
30 s es confiable.

### C2 (Crítico) — Anti-replay NO atómico (race condition)
El flujo original verificaba el nonce y registraba el acceso en **dos pasos separados**:

```
qrController.js:157  const isUsed = await accessModel.isNonceAlreadyUsed(nonce, ...)   // check
qrController.js:194  await accessModel.recordAccess({ ...accesoConcedido:true })       // set (después)
```

Entre el *check* y el *set* no hay atomicidad. **Dos escaneos simultáneos del mismo QR**
(captura de pantalla revendida, o el mismo QR en dos torniquetes) pasan ambos
`isNonceAlreadyUsed` (los dos ven "no usado") y **ambos abren la puerta**. Además, si Redis
está caído, `isNonceAlreadyUsed` solo consulta la DB sin ninguna garantía de unicidad →
**fail-open**. Nótese el contraste: el flujo de *tickets* sí es atómico
(`accessModel.consumeTicketAtomically`, mutex Redis + UPDATE check-and-set), pero el de QR no.

**Fix (de raíz):** `accessModel.claimQrNonceAtomically()` reclama el nonce en dos capas
atómicas y **fail-closed**:
1. **Redis** `SET qr:nonce:{nonce} NX PX <ttl>` → rechazo instantáneo del 2.º escaneo.
2. **DB** `INSERT` en la nueva tabla `qr_nonces_consumidos` (nonce = **PRIMARY KEY**): una
   violación de unicidad (`23505`) = replay, **incluso sin Redis**. Migración `005`.

`qrController.verifyQr` ahora: expiración → membresía → **claim atómico** → concesión. Si el
claim no puede garantizarse (error de DB), responde `503` sin abrir el torniquete.

---

## Eje 2 — Conexiones críticas (ZkAdms / sockets de hardware)

### C1 (Crítico) — Endpoints ADMS `/iclock/*` abiertos
`zkAdmsRoutes.js:32-42` monta `getrequest`, `devicecmd`, `c/cdata` y `registry` **sin ningún
middleware de autenticación**. Consecuencias reales:

- `GET /iclock/getrequest?SN=<cualquiera>` devuelve la cola de comandos en texto plano, que
  incluye `DATA UPDATE BIODATA ... Tmp=<plantilla facial base64>` (`zkAdmsService.js:138`):
  **exfiltración de biometría facial** + PINs + nombres.
- `POST /iclock/c/cdata?table=ATTLOG` inyecta registros de acceso falsos en
  `historial_accesos` (`zkAdmsService.js:311-359`): **manipulación del log de auditoría**.
- `POST /iclock/devicecmd` con `ID=<cmd>&Return=0` marca como ejecutado un borrado que la
  terminal nunca hizo (`zkAdmsService.js:261-298`): un socio **revocado sigue enrolado**.

**Fix:** nuevo middleware `admsDeviceAuth.js` aplicado a las 4 rutas: **allowlist de números
de serie** (`ZK_ALLOWED_SERIALS`) + **clave de push compartida** (`ZK_PUSH_KEY`, header
`x-adms-key` o `?key=`) comparada con `timingSafeEqual`. Fail-closed cuando está configurado;
si aún no lo está, registra una **advertencia crítica** para no romper despliegues legacy.
Ambas variables deben establecerse en producción.

### A1 (Alto) — Memory leak en `PIN_CACHE`
`zkAdmsService.js:26` define `const PIN_CACHE = new Map()` que solo se llena
(`resolvePinToUserId` → `PIN_CACHE.set`) y **nunca evita crecer**: el chequeo de TTL evita
usar entradas viejas pero no las borra. En un contenedor de larga vida con muchos PINs
distintos (incluidos `zk_pin_*_unresolved`) el Map crece sin cota.
**Fix:** tope `PIN_CACHE_MAX = 5000` con evicción de la entrada más antigua + borrado de las
expiradas al leerlas.

### A3 (Medio) — Colisión de `generateCommandId`
`Math.floor(Date.now()/1000) + random(1000..9999)` (`zkAdmsService.js:90-92`) puede repetir
ID en el mismo segundo; como `processCommandResult` resuelve por `command_id`, una colisión
marca como `completed` **un comando distinto**. Smoke test: 4 colisiones en 100k.
**Fix:** contador **monotónico** sembrado aleatoriamente (0 colisiones en 1M) en rango 2^31.

### A2 (Alto) — Bloqueo y fugas en `reception_controller.js`
- **Lockup del relé:** si el `setTimeout` que reabre el circuito lanza al escribir
  `RELAY_CMD_CLOSE`, la línea `isRelayBusy = false` se salta → el flag queda `true` para
  siempre y **el torniquete no vuelve a abrir**. **Fix:** `try/finally` + un **watchdog**
  (`pulseDurationMs + 2s`) que fuerza el reset pase lo que pase (`releaseRelayBusy`).
- **Fuga de sockets:** los handlers `on('error')`/`on('close')` hacían `relayPort = null`
  **sin** `removeAllListeners()` ni `close()`, dejando fd/listeners colgados en cada ciclo de
  reconexión (auto-heal cada 3 s). **Fix:** `safeReleaseSerialPort()` que limpia listeners y
  cierra el fd antes de nulificar (relé y lector QR).
- Los timeouts de `axios` (3.5 s) y el body parser de ADMS (`limit: '2mb'`) ya acotan
  bloqueos/desbordes — correctos.

---

## Eje 3 — Validación de Turnstile

`turnstileAuth.js` es **sólido**: extrae la clave de `x-turnstile-key`/`x-api-key`/
`Authorization: ApiKey`, exige longitud igual y compara con `timingSafeEqual` (anti timing
attack). No hay stubs, modo debug ni default débil del lado servidor. La creación de tickets
(`ticketRoutes.js`) exige JWT y los pases de cortesía se acuñan por el endpoint interno
protegido con `INTER_SERVICE_SECRET`. **Sin exposición.**

**M1 (Medio):** el *cliente* de recepción sí trae secretos por defecto hardcodeados
(`reception_controller.js:29` → `'turnstile_secret_key_prod_2026'`; `cash_payment_client.js`
→ `'gympro_cash_rec01_changeme'`). No comprometen al servidor (que valida contra su env), pero
son un *code smell*: deben fallar-cerrado si la env no está, no caer a un valor predecible.

---

## Archivos entregados

**Correcciones (código):**
```
docs/database/schemas/migrations/005_add_qr_nonces_consumidos.sql   (C2)
services/access-service/src/models/accessModel.js                   (C2: claimQrNonceAtomically)
services/access-service/src/controllers/qrController.js             (C2: verifyQr atómico)
services/access-service/src/middlewares/admsDeviceAuth.js           (C1: auth ADMS)
services/access-service/src/routes/zkAdmsRoutes.js                  (C1: wiring)
services/access-service/src/config/environment.js                  (C1: ZK_ALLOWED_SERIALS/ZK_PUSH_KEY)
services/access-service/src/services/zkAdmsService.js               (A1 cache, A3 IDs)
services/reception-hardware-controller/node/reception_controller.js (A2 watchdog + limpieza serie)
```

**Acción requerida en producción:** aplicar migración `005`, y definir `ZK_ALLOWED_SERIALS`
y `ZK_PUSH_KEY` (además de configurar la clave de push en cada terminal SpeedFace-V5L).

Todos los archivos tocados pasan `node --check`; la lógica de IDs y del claim/caché se validó
con smoke tests.
