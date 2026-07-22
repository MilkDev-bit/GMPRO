# Despliegue en Railway

Guía para desplegar los 5 microservicios de GymPro desde el monorepo.

`reception-hardware-controller` NO se despliega aquí: es un controlador de
hardware que corre en la máquina de recepción del gimnasio, no en la nube.

---

## Concepto clave: un repo, varios servicios

Railway conecta **un** repositorio de GitHub y crea **un servicio por cada
Dockerfile**. El detalle crítico de este monorepo:

> Cada Dockerfile hace `COPY packages_shared` y `COPY services/xxx`, así que
> necesita el **contexto de build en la raíz del repo**, no en la carpeta del
> servicio.

Por eso, para cada servicio en Railway:
- **Root Directory**: se deja vacío (= raíz del repo).
- **Config File**: se apunta al `railway/<servicio>.json` correspondiente, que
  fija el `dockerfilePath`.

Los archivos `railway/*.json` ya están creados con esa configuración.

---

## Paso 0 · Requisitos

```bash
git push origin main        # Railway despliega desde GitHub
```

Cuenta en railway.app conectada a `github.com/MilkDev-bit/GMPRO`.

---

## Paso 1 · Proyecto y Redis

1. En Railway: **New Project ▸ Deploy from GitHub repo ▸ GMPRO**.
2. Cuando cree el primer servicio, bórralo de momento (lo configuramos bien
   en el paso 2).
3. **New ▸ Database ▸ Add Redis**. Railway lo provisiona y expone
   `REDIS_URL` en su red privada. Anótalo: lo referenciarás desde los
   servicios que lo usan (ai, fitness).

⚠ Redis de Railway es Redis normal, **sin RediSearch**. El caché semántico
que queda pendiente necesitaría un Redis Stack externo (Redis Cloud tiene
plan gratuito con RediSearch). Para lo que hay hoy, el Redis de Railway basta.

---

## Paso 2 · Crear los 5 servicios

Repite esto para cada servicio (auth, access, payment, fitness, ai):

1. **New ▸ GitHub Repo ▸ GMPRO** (sí, el mismo repo cada vez).
2. En **Settings** del servicio:
   - **Root Directory**: vacío.
   - **Config as code / Railway Config File**: `railway/<servicio>.json`
     (p. ej. `railway/ai.json`).
3. Ponle nombre claro: `auth-service`, `ai-service`, etc.

Railway detecta el Dockerfile del config y construye con la raíz como
contexto. El `startCommand`, el `/health` y la política de reinicio ya vienen
en el JSON.

Orden recomendado de creación (por dependencias): **auth → access, payment,
fitness → ai**.

---

## Paso 3 · Variables de entorno

Cada servicio necesita su bloque. Railway ▸ servicio ▸ **Variables**.

### Compartidas por TODOS (deben ser idénticas)

```
NODE_ENV=production
JWT_SECRET=<el mismo de tu .env local, o genera uno nuevo>
INTER_SERVICE_SECRET=<el mismo en los 5>
SUPABASE_URL=https://<tu-proyecto>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<sb_secret_... o el JWT eyJ...>
```

⚠ `JWT_SECRET` e `INTER_SERVICE_SECRET` DEBEN coincidir byte a byte entre los
5 servicios, o la autenticación entre ellos falla. Usa `./scripts/check-secrets.sh`
en local para confirmar los valores antes de copiarlos.

### URLs internas — usa la red privada de Railway

Railway da a cada servicio un dominio interno `<nombre>.railway.internal`.
Es más rápido y no sale a internet. Ejemplos:

```
# en ai-service
FITNESS_SERVICE_INTERNAL_URL=http://fitness-service.railway.internal:3004

# en access-service
PAYMENT_SERVICE_INTERNAL_URL=http://payment-service.railway.internal:3003

# en ai-service, si usa Redis
REDIS_URL=${{Redis.REDIS_URL}}     # referencia al plugin Redis
```

`${{Redis.REDIS_URL}}` es la sintaxis de Railway para referenciar la variable
de otro servicio: no copies el valor a mano.

### Específicas por servicio

- **ai-service**: `AI_PROVIDER=gemini`, `GEMINI_API_KEY`, `GEMINI_MODEL`,
  `GEMINI_MODEL_PRO`, `SUPABASE_DB_SCHEMA`.
- **payment-service**: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
  `CASH_PAYMENT_API_KEY`, `CORS_ALLOWED_ORIGINS`.
- **access-service**: `TURNSTILE_API_KEY`, `PAYMENT_SERVICE_INTERNAL_URL`,
  `CORS_ALLOWED_ORIGINS`, `JWT_ALGORITHM`.
- **fitness-service**: `RESEND_API_KEY` (opcional; sin ella los correos se
  simulan en consola), `REDIS_URL`.

Consulta el `.env` local de cada servicio para la lista completa: las
variables que valida al arrancar están en `src/config/environment.js`.

**NO** definas `PORT`: Railway lo inyecta y los servicios ya lo leen de env.

---

## Paso 4 · Dominios públicos

Solo los servicios a los que llega la app móvil necesitan dominio público.
En cada uno: **Settings ▸ Networking ▸ Generate Domain**.

Los que hablan solo entre servicios (por red interna) pueden quedarse sin
dominio público — es más seguro.

Actualiza las URLs en la app Flutter (`lib/core/config/app_config.dart`, la
rama remota) con los dominios que Railway genere.

---

## Paso 5 · Verificar

```bash
# Cada servicio con dominio público:
curl -s https://<servicio>-production.up.railway.app/health | jq
```

Y en los logs de Railway (pestaña Deploy Logs de cada servicio) busca:
- `escuchando en :<puerto>` — arrancó.
- ai-service: `Modelos verificados contra el proveedor` — la clave y el
  modelo son válidos en producción.
- ningún `Configuración inválida` ni crash loop.

---

## Errores frecuentes

**`COPY failed: packages_shared not found`** → el Root Directory no está
vacío, o el servicio no está usando el `railway/*.json`. El contexto debe ser
la raíz del repo.

**`Configuración inválida: JWT_SECRET`** → falta la variable o es más corta
de 64 caracteres. Cópiala de tu `.env` local ya validado.

**Un servicio no encuentra a otro** → estás usando el dominio público en una
llamada interna, o el puerto no coincide. Usa
`http://<nombre>.railway.internal:<puerto>`.

**El deploy se reconstruye entero en cada push aunque cambies un solo
servicio** → normal con monorepo; Railway reconstruye los servicios cuyo
contexto tocó. Para acotarlo, en Settings ▸ **Watch Paths** pon
`services/ai-service/**` y `packages_shared/**` por servicio.

---

## Coste

5 servicios + Redis en el plan de Railway consumen recursos incluso ociosos.
Para un entorno de pruebas, considera desplegar solo `auth` + `ai` primero y
añadir el resto cuando lo necesites.
