# Audit 02 — Backend/API/Web · A04 Criptografía · A05 Inyección · A06 Diseño inseguro

> Alcance: backend (5 microservicios Node/Express + `packages_shared/security`),
> frontend web (`apps/admin-web`) y, donde toca inyección de comandos, el
> controlador de hardware (`services/reception-hardware-controller`). Basado en
> `audit-00-mapeo.md`. Referencia: OWASP Top 10:2025. Fecha: 2026-07-24.
> Método: revisión estática con evidencia `archivo:línea`; sin hallazgos
> inventados; limitaciones (TLS/consola cloud) indicadas.

## Tabla resumen

| ID | Categoría | Hallazgo | Severidad | Evidencia |
|----|-----------|----------|-----------|-----------|
| A04-1 | Criptografía | JWT/INTER_SERVICE = secreto **simétrico compartido** entre los 5 servicios | Baja (diseño) | `services/*/.env.example` (JWT_SECRET ×5); `jwtVerify.js` |
| A04-2 | Criptografía | `ENCRYPTION_KEY` en auth-service **declarada pero sin uso** (config muerta) | Baja | `auth-service/environment.js:77,140`; sin referencias en `src/**` |
| A04-3 | Criptografía | Hashing, cifrado en reposo y tokens correctos | ✅ Correcto | `passwordController.js:81,119`; `cryptoService.js:33-118`; `tokenService.js:66-67` |
| A04-4 | Criptografía | TLS/certificados a nivel de edge no verificables desde el repo | Info (pendiente) | HSTS en `helmetConfig.js:85`; Railway |
| A05-1 | Inyección | SQL/NoSQL (PostgREST `.or/.ilike`) saneado; RPC parametrizado | ✅ Correcto | `postgrestSanitizer.js:20`; `userModel.js:448`; `offerModel.js:64` |
| A05-2 | Inyección | Sin inyección de comandos (no `child_process`; Python HW sin `subprocess`) | ✅ Correcto | grep `child_process/subprocess` = 0 |
| A05-3 | Inyección | XSS/SSTI: React auto-escapa; emails con `escapeHtml`; sanitizer global | ✅ Correcto | `index.js:73,120`; `emailTemplates.js:38,57` |
| A06-1 | Diseño inseguro | **Sin threat model formal/consolidado** (STRIDE, DFD, límites de confianza) | Media | `docs/` (auditorías ad-hoc; sin artefacto de modelado) |
| A06-2 | Diseño inseguro | Flujos críticos con controles arquitectónicos sólidos | ✅ Correcto | brute-force, replay QR, idempotencia webhook, reuse refresh |

**Limitación global:** la terminación TLS y la configuración de certificados
ocurren en el edge de Railway; no son auditables desde el repositorio (se requiere
acceso a la consola cloud). A nivel de aplicación, HSTS con `preload` está activo.

---

## A04 — Fallos criptográficos · Severidad global: Baja

### Controles correctos (A04-3)
- **Hashing de contraseñas:** `bcrypt` con `BCRYPT_ROUNDS` validado a rango 10–15
  (`auth-service/environment.js:71-74`); `bcrypt.hash(newPassword, rounds)`
  (`passwordController.js:81`) y `bcrypt.compare` (`:119`). Salt automático de bcrypt.
- **Cifrado en reposo (QR de acceso):** **AES-256-GCM** autenticado
  (`access-service/cryptoService.js:33`), IV aleatorio de 12 bytes por operación
  (`:51`), empaquetado `[version][IV][authTag][ciphertext]` y **verificación del
  authTag** en descifrado (`setAuthTag` + `decipher.final` lanza si fue manipulado,
  `:105-115`). Clave = 64 hex = 32 bytes (AES-256), validada en env.
- **Tokens:** refresh y reset se guardan **hasheados con SHA-256**, nunca en claro
  (`tokenService.js:66-67`, `refreshTokenModel.js:43,65`); los tokens se generan con
  `crypto.randomBytes(64|32)` (CSPRNG), no `Math.random`.
- **JWT:** HS512 con secreto ≥ 64 chars y whitelist de algoritmo (rechaza `alg:none`)
  — ver `jwtVerify.js` (auditado en `audit-01`).
- **Sin primitivas débiles:** no hay MD5/SHA1/DES/RC4/ECB ni `createCipher(`
  (deprecado); solo `createCipheriv` (grep de algoritmos débiles = 0 reales).

### A04-1 (Baja, diseño) — Secreto simétrico compartido entre servicios
`JWT_SECRET` (y `INTER_SERVICE_SECRET`) son **simétricos y compartidos** por los 5
servicios (`services/*/.env.example` declaran `JWT_SECRET`). Cualquier servicio
puede **firmar** tokens válidos para todos.
- **Impacto:** el compromiso de UN servicio (o de un `.env`) permite forjar JWT
  aceptados por todo el backend; no hay separación de privilegios de firma.
- **Remediación:** migrar a **RS256/EdDSA (asimétrico)**: auth-service guarda la
  clave privada y firma; los demás verifican con la pública (distribuible sin
  riesgo). Alternativa mínima: secretos distintos por par emisor/verificador y
  rotación documentada.

### A04-2 (Baja) — `ENCRYPTION_KEY` sin uso en auth-service
`ENCRYPTION_KEY` es **obligatoria** (`environment.js:77` `length === 64`; exportada
`:140`; en la lista `REQUIRED_ENV` de `main.js:29`), pero **no se referencia en
ningún módulo de cripto** de auth-service (grep en `src/**` excluyendo config/main = 0).
- **Impacto:** config muerta que (a) obliga a aprovisionar una clave que no protege
  nada y (b) da **falsa sensación de cifrado en reposo** de PII en auth_service_db.
  Nota: el cifrado real en reposo vive en access-service (`AES_ENCRYPTION_KEY`, sí usado).
- **Remediación:** decidir explícitamente — o **eliminar** la variable, o **cablearla**
  para cifrar PII sensible en reposo (p. ej. datos biométricos/`pin_terminal`) con
  AES-256-GCM reutilizando el patrón de `cryptoService.js`.

### A04-4 (Info) — TLS/certificados
No auditable desde el repo. **Qué necesitaría:** consola de Railway (versión TLS
mínima, cifrados, HSTS en el edge, redirección HTTP→HTTPS efectiva).

---

## A05 — Inyección · Severidad global: Sin hallazgos (residual Baja)

### SQL / NoSQL (A05-1) — correcto
El acceso a datos usa supabase-js/PostgREST con **valores parametrizados**; las
únicas interpolaciones en filtros `.or()`/`.ilike()` van **saneadas**:
- Utilidad dedicada `fitness-service/utils/postgrestSanitizer.js:20` — neutraliza
  `, ( ) % * : \\ " ' \`` y caracteres de control antes de interpolar.
- `fitness foodController.js:130` e `internalController.js:94` usan `safeQuery`/`safeName`.
- `auth userModel.js:448` — `safe = search.replace(/[^a-zA-Z0-9@._\-\s]/g,'')`.
- `payment offerModel.js:64` — `.ilike('codigo', safe)` con comodines escapados.
- `payment growthRetentionWorker.js:50,148` — `.or(...)` con **fechas calculadas en
  servidor** (no input de usuario).
- **RPC** (`assign_pin_terminal`, `increment_offer_usage`, `registrar_pago_efectivo`)
  reciben parámetros **enlazados** (`{ p_codigo: codigo }`), no concatenación SQL.

### Comandos / código (A05-2) — correcto
- **Sin `child_process`/`exec`/`spawn`** en los servicios Node. El único `eval` es
  `redisClient.eval(luaScript, ...)` (`accessModel.js:269`): es **Redis Lua** con
  `KEYS`/`ARGV` enlazados, no ejecución de SO.
- **Hardware Python** (`reception-hardware-controller/python`): sin `os.system`,
  `subprocess`, `eval`, `exec` ni `shell=True` (grep = 0). La comunicación es por
  `pyserial`/`pyusb`/ESC-POS (API tipada, no shell).

### XSS / SSTI (A05-3) — correcto
- **Frontend:** React escapa por defecto; **no** hay `dangerouslySetInnerHTML` ni
  `innerHTML` en `apps/admin-web/src` (solo un comentario que lo prohíbe en `api.ts:8`).
- **Emails:** no hay motor de plantillas server-side (no SSTI); las variables se
  interpolan con `escapeHtml()` sobre `< > & " '` (`emailTemplates.js:38,57,79`),
  cerrando inyección de markup vía nombre de usuario/rutina.
- **Defensa global:** `security.applyGlobal` monta `inputSanitizer`
  (`blockOnThreat:true`), `hpp`, `express.json({strict:true})` y límite de payload
  antes de las rutas (`index.js:73,105-120`).

> Verdicto A05: no se identificaron vectores de inyección explotables en el código
> revisado (backend, web y hardware).

---

## A06 — Diseño inseguro · Severidad global: Media (por ausencia de modelado formal)

### Controles arquitectónicos correctos (A06-2)
Los flujos críticos tienen controles de diseño, no solo parches:
- **Anti fuerza bruta en login (defensa en capas):** limiter por **IP**
  (`createAuthRateLimiter`, max 5, `skipSuccessfulRequests`) **y** limiter por
  **cuenta** (`loginAccountRateLimiter`, anti-brute-force distribuido rotando IPs)
  aplicados ambos a `/login` (`auth main.js:107-153`), más **bloqueo temporal de
  cuenta** ("Cuenta bloqueada temporalmente", `authController.js:149`).
- **Anti-enumeración de cuentas:** login responde genérico
  "Email o contraseña incorrectos" (`authController.js:156`); `forgot-password`
  responde SIEMPRE genérico y envía el token **por email** (no en la respuesta HTTP),
  guardándolo **hasheado** (`passwordController.js:29-55`).
- **Política de contraseñas:** min 8, mayúscula, número y carácter especial
  (`authRoutes.js:70-73`).
- **Robo/replay de sesión:** detección de **reuso de refresh token** con revocación
  de la familia y mensajes genéricos (`authController.js:303,343-391`).
- **Replay de acceso físico (QR):** nonce de **un solo uso** (Redis
  `access:nonce_used:` + `usado_at` en BD) + **mutex distribuido** `SET NX PX 5000`
  + UPDATE condicional (`accessModel.js:25,64,169-206`).
- **Idempotencia financiera:** claim atómico del evento Stripe (PK
  `webhook_events_procesados`) e incremento atómico de cupones (auditado en fases
  previas); firma HMAC del webhook verificada.
- **Autorización entre servicios (M2M):** `requireInterServiceSecret` /
  `createInterServiceAuthMiddleware` con comparación timing-safe
  (`access/internalRoutes.js:29,41`; `fitness main.js:94`).
- **Aislamiento de datos:** RLS deny-all + `service_role` (modelo de `audit-00`).
- **MFA/passwordless:** WebAuthn/passkeys presente (`passkeyController.js`).

### A06-1 (Media) — Ausencia de threat model formal
**Evidencia:** `docs/` contiene auditorías por servicio (`docs/guides/*-audit.md`,
`docs/security/BACKEND_SECURITY_AUDIT.md`) y este propio ciclo, pero **no existe un
artefacto de modelado de amenazas consolidado**: sin diagramas de flujo de datos
(DFD), sin límites/zonas de confianza explícitos, sin matriz STRIDE por flujo, sin
registro de decisiones y supuestos de seguridad.
- **Impacto:** los (buenos) controles existen de forma **ad-hoc**; sin modelado
  sistemático es fácil que un flujo nuevo (p. ej. un endpoint que acepte URL de
  usuario → SSRF, ver `audit-01` A01-3) nazca sin su control. Dificulta priorizar y
  auditar cobertura.
- **Remediación:** crear `docs/security/threat-model.md` con: (1) DFD de los flujos
  críticos (registro/login, pago+webhook, acceso físico QR, sincronización
  biométrica, IA/PII); (2) límites de confianza (cliente móvil ↔ API ↔ Supabase ↔
  hardware); (3) STRIDE por flujo mapeado a los controles ya existentes y a los
  huecos; (4) supuestos y decisiones (p. ej. secreto JWT simétrico, A04-1). Integrar
  su revisión al checklist de PR para features que toquen esos flujos.

### A06-2 (Baja, diseño) — Secreto de firma compartido
Cruce con **A04-1**: el modelo de confianza asume que todos los servicios son
igualmente confiables para firmar tokens. Documentarlo como decisión explícita en el
threat model y evaluar la migración a firma asimétrica.

---

## Priorización de remediación

| Prioridad | Acción | Hallazgo |
|-----------|--------|----------|
| 1 | Crear threat model consolidado (DFD + STRIDE + límites de confianza) | A06-1 |
| 2 | Resolver `ENCRYPTION_KEY`: eliminar o cablear a cifrado de PII en reposo | A04-2 |
| 3 | Evaluar migración JWT a RS256/EdDSA (firma asimétrica) | A04-1 / A06-2 |
| — | Verificar TLS/HSTS/redirección en consola Railway | A04-4 |

> Nota: A05 (Inyección) no arroja hallazgos; los controles (sanitizador PostgREST,
> parámetros enlazados, escape en emails, auto-escape de React, sin `child_process`)
> son adecuados. Mantener el patrón `postgrestSanitizer`/`assertSafePublicUrl` como
> requisito para cualquier nuevo punto que interpole entrada de usuario.
