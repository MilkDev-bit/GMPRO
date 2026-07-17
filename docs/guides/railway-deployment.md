# GymPro · Guía de Despliegue en Railway

> **Audiencia:** DevOps / desarrollador que configura Railway por primera vez para este proyecto.
> Esta guía asume que ya tienes una cuenta en [railway.app](https://railway.app) y la CLI instalada.

---

## Índice

1. [Prerrequisitos](#prerrequisitos)
2. [Arquitectura en Railway](#arquitectura-en-railway)
3. [Paso a paso: crear el proyecto](#paso-a-paso)
4. [Variables de entorno por servicio](#variables-de-entorno-por-servicio)
5. [Red privada entre servicios](#red-privada-entre-servicios)
6. [Webhook de Stripe](#webhook-de-stripe)
7. [Checklist de seguridad pre-producción](#checklist-de-seguridad)

---

## Prerrequisitos

```bash
# Instalar Railway CLI
npm install -g @railway/cli

# Autenticarse
railway login

# Verificar versión
railway --version
```

Dependencias externas que debes tener configuradas **antes** de hacer el deploy:
- [ ] Proyecto en [Supabase](https://supabase.com) creado con el script SQL de la Tarea 1.1
- [ ] Cuenta en [Stripe](https://stripe.com) con planes de suscripción creados
- [ ] API Key de [Google AI Studio](https://aistudio.google.com) (Gemini) o OpenAI
- [ ] Cuenta en [Resend](https://resend.com) para emails transaccionales

---

## Arquitectura en Railway

```
Railway Project: gympro-production
│
├── Service: auth-service        (Puerto interno: 3001)
├── Service: access-service      (Puerto interno: 3002)
├── Service: payment-service     (Puerto interno: 3003)
├── Service: fitness-service     (Puerto interno: 3004)
├── Service: ai-service          (Puerto interno: 3005)
│
└── Add-on: Redis                (railway.internal:6379)
```

> **Red privada Railway**: Los servicios dentro del mismo proyecto se comunican
> entre sí usando el dominio `.railway.internal` — sin salir a internet público.
> Esto reduce latencia y elimina costos de egress de red.

---

## Paso a paso

### 1. Crear el proyecto
```bash
railway init
# Nombre: gympro-production
# Environment: production
```

### 2. Agregar cada servicio desde GitHub
En Railway Dashboard → **New Service** → **GitHub Repo** → selecciona el repositorio.

Para cada microservicio:
1. **Source**: Seleccionar el mismo repo monorepo
2. **Root Directory**: `services/<nombre-servicio>` (ej: `services/auth-service`)
3. **Build Command**: Railway detecta el Dockerfile automáticamente
4. **Start Command**: se toma del Dockerfile (`CMD`)

### 3. Agregar Redis como Add-on
Railway Dashboard → **New Service** → **Add-on** → **Redis**

Copia la variable `REDIS_URL` que Railway genera y agrégala a `fitness-service` y `ai-service`.

### 4. Configurar el dominio
Para cada servicio: **Settings** → **Networking** → **Generate Domain**

---

## Variables de Entorno por Servicio

> **Cómo configurar en Railway:**
> Dashboard → Seleccionar servicio → **Variables** → **Raw Editor** → pegar contenido

> [!CAUTION]
> Railway muestra las variables en texto plano en el dashboard. Asegúrate de
> que solo los miembros del equipo con acceso al proyecto de Railway puedan
> verlas. Usa **Teams → Members** para controlar el acceso.

---

### `auth-service`

| Variable | Valor de ejemplo | Obligatoria |
|----------|-----------------|-------------|
| `NODE_ENV` | `production` | ✅ |
| `PORT` | `3001` | ✅ |
| `SUPABASE_URL` | `https://xxx.supabase.co` | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | ✅ |
| `SUPABASE_DB_SCHEMA` | `auth_service_db` | ✅ |
| `JWT_SECRET` | `[hex 128 chars]` | ✅ |
| `JWT_EXPIRES_IN` | `15m` | ✅ |
| `JWT_REFRESH_EXPIRES_IN` | `30d` | ✅ |
| `JWT_ALGORITHM` | `HS512` | ✅ |
| `BCRYPT_ROUNDS` | `12` | ✅ |
| `ENCRYPTION_KEY` | `[hex 64 chars]` | ✅ |
| `RESEND_API_KEY` | `re_xxx` | ✅ |
| `EMAIL_FROM` | `noreply@tugimnasio.com` | ✅ |
| `EMAIL_FROM_NAME` | `GymPro` | ✅ |
| `RATE_LIMIT_LOGIN_MAX` | `5` | ✅ |
| `RATE_LIMIT_LOGIN_WINDOW_MINUTES` | `15` | ✅ |
| `CORS_ALLOWED_ORIGINS` | `https://app.tugimnasio.com` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `LOG_FORMAT` | `json` | ✅ |

**Generar `JWT_SECRET`:**
```bash
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

**Generar `ENCRYPTION_KEY`:**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

---

### `access-service`

| Variable | Valor de ejemplo | Obligatoria |
|----------|-----------------|-------------|
| `NODE_ENV` | `production` | ✅ |
| `PORT` | `3002` | ✅ |
| `SUPABASE_URL` | `https://xxx.supabase.co` | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | ✅ |
| `SUPABASE_DB_SCHEMA` | `access_service_db` | ✅ |
| `JWT_SECRET` | `[mismo que auth-service]` | ✅ |
| `JWT_ALGORITHM` | `HS512` | ✅ |
| `QR_SECRET_KEY` | `[hex 64 chars]` | ✅ |
| `QR_TTL_SECONDS` | `30` | ✅ |
| `QR_ISSUER` | `gympro-access-service` | ✅ |
| `AUTH_SERVICE_INTERNAL_URL` | `http://auth-service.railway.internal:3001` | ✅ |
| `PAYMENT_SERVICE_INTERNAL_URL` | `http://payment-service.railway.internal:3003` | ✅ |
| `INTER_SERVICE_SECRET` | `[hex 64 chars]` | ✅ |
| `INTER_SERVICE_TIMEOUT_MS` | `3000` | ✅ |
| `RATE_LIMIT_QR_MAX` | `10` | ✅ |
| `RATE_LIMIT_QR_WINDOW_SECONDS` | `60` | ✅ |
| `CORS_ALLOWED_ORIGINS` | `https://app.tugimnasio.com` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `LOG_FORMAT` | `json` | ✅ |

> **Importante:** `QR_SECRET_KEY` debe tener el mismo valor en `access-service` Y en la
> variable de entorno del `scripts_local` en el dispositivo físico de recepción.

---

### `payment-service`

| Variable | Valor de ejemplo | Obligatoria |
|----------|-----------------|-------------|
| `NODE_ENV` | `production` | ✅ |
| `PORT` | `3003` | ✅ |
| `SUPABASE_URL` | `https://xxx.supabase.co` | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | ✅ |
| `SUPABASE_DB_SCHEMA` | `payment_service_db` | ✅ |
| `JWT_SECRET` | `[mismo que auth-service]` | ✅ |
| `JWT_ALGORITHM` | `HS512` | ✅ |
| `STRIPE_SECRET_KEY` | `sk_live_xxx` | ✅ |
| `STRIPE_WEBHOOK_SECRET` | `whsec_xxx` | ✅ |
| `STRIPE_PRICE_ID_MENSUAL` | `price_xxx` | ✅ |
| `STRIPE_PRICE_ID_TRIMESTRAL` | `price_xxx` | ⬜ |
| `STRIPE_PRICE_ID_ANUAL` | `price_xxx` | ⬜ |
| `STRIPE_DEFAULT_CURRENCY` | `mxn` | ✅ |
| `AUTH_SERVICE_INTERNAL_URL` | `http://auth-service.railway.internal:3001` | ✅ |
| `INTER_SERVICE_SECRET` | `[mismo en todos]` | ✅ |
| `BUSINESS_NAME` | `GymPro` | ✅ |
| `BUSINESS_RFC` | `XAXX010101000` | ✅ |
| `CORS_ALLOWED_ORIGINS` | `https://app.tugimnasio.com` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `LOG_FORMAT` | `json` | ✅ |

---

### `fitness-service`

| Variable | Valor de ejemplo | Obligatoria |
|----------|-----------------|-------------|
| `NODE_ENV` | `production` | ✅ |
| `PORT` | `3004` | ✅ |
| `SUPABASE_URL` | `https://xxx.supabase.co` | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | ✅ |
| `SUPABASE_DB_SCHEMA` | `fitness_schema` | ✅ |
| `JWT_SECRET` | `[mismo que auth-service]` | ✅ |
| `JWT_ALGORITHM` | `HS512` | ✅ |
| `SUPABASE_STORAGE_BUCKET_EXERCISES` | `exercise-media` | ✅ |
| `SUPABASE_STORAGE_PUBLIC_URL` | `https://xxx.supabase.co/storage/v1/object/public` | ✅ |
| `REDIS_URL` | `redis://default:xxx@redis.railway.internal:6379` | ⬜ |
| `EXERCISE_CATALOG_CACHE_TTL` | `3600` | ⬜ |
| `DEFAULT_PAGE_SIZE` | `20` | ✅ |
| `AUTH_SERVICE_INTERNAL_URL` | `http://auth-service.railway.internal:3001` | ✅ |
| `INTER_SERVICE_SECRET` | `[mismo en todos]` | ✅ |
| `CORS_ALLOWED_ORIGINS` | `https://app.tugimnasio.com` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `LOG_FORMAT` | `json` | ✅ |

---

### `ai-service`

| Variable | Valor de ejemplo | Obligatoria |
|----------|-----------------|-------------|
| `NODE_ENV` | `production` | ✅ |
| `PORT` | `3005` | ✅ |
| `SUPABASE_URL` | `https://xxx.supabase.co` | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | ✅ |
| `SUPABASE_DB_SCHEMA` | `ai_schema` | ✅ |
| `JWT_SECRET` | `[mismo que auth-service]` | ✅ |
| `JWT_ALGORITHM` | `HS512` | ✅ |
| `AI_PROVIDER` | `gemini` | ✅ |
| `GEMINI_API_KEY` | `AIzaSy_xxx` | ✅ (si usas Gemini) |
| `GEMINI_MODEL` | `gemini-2.0-flash` | ✅ |
| `GEMINI_MODEL_PRO` | `gemini-2.5-pro` | ⬜ |
| `AI_MAX_INPUT_TOKENS` | `4096` | ✅ |
| `AI_MAX_OUTPUT_TOKENS` | `2048` | ✅ |
| `AI_MAX_CONTEXT_MESSAGES` | `20` | ✅ |
| `AI_REQUESTS_PER_USER_PER_DAY` | `50` | ✅ |
| `AI_TEMPERATURE` | `0.4` | ✅ |
| `FITNESS_SERVICE_INTERNAL_URL` | `http://fitness-service.railway.internal:3004` | ✅ |
| `AUTH_SERVICE_INTERNAL_URL` | `http://auth-service.railway.internal:3001` | ✅ |
| `INTER_SERVICE_SECRET` | `[mismo en todos]` | ✅ |
| `REDIS_URL` | `redis://default:xxx@redis.railway.internal:6379` | ⬜ |
| `AI_RECOMMENDATION_CACHE_TTL` | `86400` | ⬜ |
| `AI_LOG_PROMPTS` | `false` | ✅ |
| `CORS_ALLOWED_ORIGINS` | `https://app.tugimnasio.com` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `LOG_FORMAT` | `json` | ✅ |

---

## Red Privada entre Servicios

Railway asigna automáticamente un hostname interno a cada servicio usando el formato:

```
http://<nombre-servicio>.railway.internal:<puerto>
```

**Reglas de comunicación entre servicios:**

```
auth-service      → (no llama a otros servicios internos)
access-service    → auth-service:3001, payment-service:3003
payment-service   → auth-service:3001
fitness-service   → auth-service:3001
ai-service        → auth-service:3001, fitness-service:3004
```

> [!NOTE]
> Los hostnames `.railway.internal` SOLO funcionan dentro del mismo proyecto Railway.
> Para testing desde tu máquina local, usar los dominios públicos generados por Railway.

---

## Webhook de Stripe

El `payment-service` necesita recibir eventos de Stripe (pagos completados, fallos, etc.).

### Configurar en Stripe Dashboard:

1. **Ir a:** dashboard.stripe.com → **Developers** → **Webhooks** → **Add endpoint**
2. **Endpoint URL:** `https://payment-service.up.railway.app/webhooks/stripe`
3. **Events a escuchar:**
   - `invoice.paid` — renovación exitosa → extender `valido_hasta`
   - `invoice.payment_failed` — fallo → cambiar estado a `pendiente_pago`
   - `customer.subscription.deleted` — cancelación → cambiar estado a `cancelada`
   - `customer.subscription.updated` — cambios de plan
4. **Copiar el Signing Secret** → configurarlo como `STRIPE_WEBHOOK_SECRET` en Railway

> [!IMPORTANT]
> El endpoint de webhooks **NO debe tener JWT middleware**. La autenticación se hace
> verificando la firma de Stripe con `stripe.webhooks.constructEvent()`.
> Sin embargo, debe aceptar el **body como raw buffer** (no parsear como JSON antes).

---

## Checklist de Seguridad

### Pre-deploy obligatorio:
- [ ] Todos los `JWT_SECRET`, `ENCRYPTION_KEY`, `QR_SECRET_KEY`, `INTER_SERVICE_SECRET` son únicos y aleatorios (≥64 chars hex)
- [ ] `STRIPE_SECRET_KEY` usa la clave de **producción** (sk_live_), no la de test
- [ ] `BCRYPT_ROUNDS` es 12 o superior
- [ ] `NODE_ENV=production` en todos los servicios
- [ ] `AI_LOG_PROMPTS=false` en producción
- [ ] `CORS_ALLOWED_ORIGINS` solo contiene dominios propios (sin wildcards)
- [ ] Los `.env` reales NO están en Git (verificar con `git status`)

### Post-deploy verificar:
- [ ] Endpoint `/health` de cada servicio responde 200
- [ ] Healthchecks en Railway muestran estado verde
- [ ] Logs de Railway no muestran `JWT_SECRET` u otras credenciales en texto plano
- [ ] Webhook de Stripe muestra estado "Active" en Stripe Dashboard
- [ ] Rate limiting funciona (probar con Postman > 5 requests/minuto)
