# Auditoría de seguridad — `auth-service`

**Rol:** CISO / Criptógrafo Senior. **Alcance:** Passkeys (FIDO2/WebAuthn), JWT
(access/refresh/revocación), recuperación de contraseña y sanitización de datos médicos.
**Método:** revisión estática + smoke tests (`node --check` + pruebas de origen/XSS/TTL).
No hubo ejecución contra Supabase/Redis.

## Resumen ejecutivo (priorizado por severidad)

| # | Hallazgo | Archivo:línea | Severidad | Estado |
|---|---|---|---|---|
| A1 | **Bypass de origen WebAuthn** por `origin.includes(RP_ID)` (substring) → derrota la resistencia a phishing | `passkeyController.js:135,299` (orig.) | **CRÍTICO** | Corregido |
| A2 | **TTL de challenge = 300 s (5 min)** → viola el requisito de < 2 min | `passkeyModel.js:24` | Alto | Corregido |
| A3 | **`userModel.findOrCreateByOAuth` usa `bcrypt`/`crypto`/`env` sin importarlos** → `ReferenceError`, el alta OAuth revienta (500) | `userModel.js:316` | Alto | Corregido |
| A4 | **Hash APK Android por defecto hardcodeado** → origen nativo predecible si falta la env | `passkeyController.js:30` (orig.) | Medio | Corregido |
| A5 | **Sin sanitización server-side de datos médicos** (`historial_clinico`, `contacto_emergencia`) → stored XSS | `userModel.js:updateProfile`, `authRoutes.js` (comentario falso) | Medio | Corregido |
| A6 | **Map de challenges en memoria sin purga** → fuga de memoria si Redis cae | `passkeyModel.js:15` | Medio | Corregido |
| A7 | `logger.warning` (método inexistente en winston) → lanzaría en el fallback | `passkeyModel.js:56` | Bajo | Corregido |
| A8 | Reset/cambio de contraseña no invalida **access tokens** vigentes (solo refresh) | `userModel.js:updatePassword` | Bajo | Señalado |
| OK | Firma JWT, algoritmo, revocación, rate-limit, hashing de reset tokens, anti-SQLi | varios | — | Correcto |

---

## Eje 1 — Robustez de Passkeys (FIDO2/WebAuthn)

**Base sólida:** la verificación de firma usa `@simplewebauthn/server`
(`verifyRegistrationResponse`/`verifyAuthenticationResponse`), criptográficamente
correcta; los challenges son de un solo uso (`getAndRemoveChallenge`) y las rutas de
verificación heredan el `authRateLimiter` por IP (montado en `/api/v1/auth`) → hay
protección anti-fuerza-bruta.

### A1 (Crítico) — Bypass de origen (phishing)
`expectedOrigin` aceptaba el origen si `origin.includes(RP_ID)`
(`passkeyController.js:135` y `:299`). Al ser un match por **substring**, orígenes
maliciosos pasaban la verificación:

```
https://gympro-ai.com.attacker.com   → includes('gympro-ai.com') = true  ❌
https://evil.com/?x=gympro-ai.com     → includes('gympro-ai.com') = true  ❌
```

Esto **anula la resistencia a phishing** que es la razón de ser de WebAuthn. Además,
el fallback `return !env.IS_PRODUCTION` aceptaba **cualquier** origen fuera de prod.

**Fix:** helper `isAllowedOrigin()` con match **exacto** para orígenes nativos y
parseo con `new URL()` para web, exigiendo `hostname === RP_ID` o subdominio real
(`.RP_ID`) sobre HTTPS. Smoke test: los 3 vectores de bypass ahora se **rechazan**;
`gympro-ai.com` y `app.gympro-ai.com` se aceptan.

### A2 (Alto) — TTL de challenge > 2 min
El TTL por defecto era **300 s** (`passkeyModel.js:24`), incumpliendo el requisito de
expiración estricta < 2 min. **Fix:** default a **90 s** con **tope duro de 120 s**
(`Math.min(ttl, 120)`), imposible configurar por encima.

### A4 (Medio) — Hash APK por defecto
`android:apk-key-hash:${process.env.ANDROID_APK_KEY_HASH || '4S6C2M9k...'}`
(`:30`) confiaba en un hash **hardcodeado** si faltaba la env → un APK con ese hash
sería aceptado. **Fix:** **fail-closed** — el origen Android solo se incluye si
`ANDROID_APK_KEY_HASH` está definida.

### A6 (Medio) — Fuga de memoria en fallback
`inMemoryChallenges` (Map) solo se limpiaba al leer; challenges abandonados quedaban
para siempre. **Fix:** barrido periódico (60 s, `unref`) + tope de 10 000 entradas
con evicción de la más antigua.

---

## Eje 2 — Configuración de tokens JWT (correcta)

- **Secreto:** de env, `JWT_SECRET.length >= 64` validado con fail-fast
  (`jwtVerify.js:22`, `environment.js:28`). No hardcodeado.
- **Algoritmo robusto:** whitelist `['HS256','HS384','HS512']` (`environment.js:31`) y
  `jwt.verify(..., { algorithms:[JWT_ALGORITHM] })` → **rechaza `alg:none`**
  (`jwtVerify.js:76-79`). HS512 por defecto.
- **TTL corto + revocación:** access token con `expiresIn` de env y `jti`; logout
  añade el `jti` a una **blacklist en Redis** con TTL = vida restante
  (`tokenService.js:84-95`, `authController` logout).
- **Refresh tokens:** opacos, almacenados como **SHA-256** (`tokenService.js:59-63`);
  logout limpia `refresh_token_hash` en DB y el refresh implementa **rotación**.
  `updatePassword`/`softDelete` ponen `refresh_token_hash = null` (invalida sesiones).

### A8 (Bajo) — Access tokens tras cambio de contraseña
`updatePassword` invalida los **refresh** tokens pero los **access** tokens ya
emitidos siguen válidos hasta su `exp` (no hay forma de blacklistear todos los `jti`
de un usuario). Mitigado por el TTL corto. **Recomendación:** añadir un claim/columna
`password_changed_at` y rechazar en `jwtVerify` los tokens con `iat <` ese valor.

---

## Eje 3 — Recuperación de contraseña y sanitización

### Reset tokens (correcto)
`generatePasswordResetToken` genera 32 bytes aleatorios y almacena **solo el
SHA-256** (`tokenService.js:113-117`); `resetTokenModel.create` guarda el `hash`
(`passwordController.js:43-44`). Un leak de DB **no** expone tokens usables. Además:
un solo uso (`usado`), expiración (DEFAULT 1 h) e invalidación de tokens previos.
La búsqueda es por hash con `usado=false` y `expira_en > now`. **Sin observaciones.**

### A3 (Alto) — Bug latente en alta OAuth
`userModel.js` **no importaba** `bcrypt`, `crypto` ni `env`, pero
`findOrCreateByOAuth` los usa (`:316`) para crear el usuario con contraseña
aleatoria. Cualquier alta nueva vía Google/Apple lanzaba `ReferenceError` → **500**.
**Fix:** añadidos los tres `require` al inicio del modelo.

### A5 (Medio) — XSS en datos médicos / SQLi
- **SQL injection clásico: NO explotable.** El cliente de Supabase/PostgREST
  parametriza las queries; `userModel` nunca concatena SQL. (El único punto a vigilar
  eran los filtros `.or()` de otros servicios, ya saneados aparte.)
- **Stored XSS: sí era posible.** `historial_clinico` (JSONB libre) y
  `contacto_emergencia` se guardaban verbatim (`updateProfile`); un `<script>`
  inyectado se ejecutaría si el frontend lo renderiza sin escapar. Irónicamente, el
  header de `authRoutes.js` afirmaba que "los datos ya pasaron por inputSanitizer.js"
  — **ese archivo no existía**.
- **Fix:** creado `middlewares/inputSanitizer.js` (drop-in) que neutraliza etiquetas
  HTML, handlers inline (`onerror=`), esquemas (`javascript:`) y caracteres de
  control, recursivamente sobre JSONB anidado y con límites anti-DoS. Cableado en
  `/register` y documentado para la futura ruta de perfil/datos médicos
  (`sanitizeFields(['historial_clinico','contacto_emergencia', ...])`).
  Smoke test: `<script>alert(1)</script>` → `alert(1)`; `<img onerror=...>` → `""`.

> La defensa primaria contra XSS sigue siendo el **output-encoding en el cliente**;
> este saneo de entrada es defensa en profundidad, como pide el brief.

---

## Archivos entregados

```
services/auth-service/src/controllers/passkeyController.js   (A1, A4)
services/auth-service/src/models/passkeyModel.js             (A2, A6, A7)
services/auth-service/src/models/userModel.js                (A3)
services/auth-service/src/middlewares/inputSanitizer.js      (A5, nuevo)
services/auth-service/src/routes/authRoutes.js               (A5 wiring)
```

Todos pasan `node --check` y la lógica (origen estricto, saneo XSS, tope de TTL) se
validó con smoke tests. Recomendación pendiente (A8): claim `password_changed_at`
para invalidar access tokens tras cambio de credenciales.
