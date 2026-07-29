# GymPro · Panel de Administración (web)

Stack: **React 18 + Vite + TypeScript + TailwindCSS + React Router**.
Cliente web para staff/admin: dashboard financiero, miembros, suscripciones y ofertas.

## Arranque
```bash
cd apps/admin-web
cp .env.example .env      # ajusta las URLs de los microservicios
npm install
npm run dev               # http://localhost:5173
npm run build             # bundle de producción en dist/
```

## Seguridad
- Login contra `auth-service` con **gate de rol** (solo `staff`/`admin` entran; los socios se rechazan).
- El **access token vive en memoria** (no en localStorage) → menor superficie de robo por XSS.
  La sesión se rehidrata vía `/refresh` (cookie httpOnly) al recargar.
- React **escapa el render por defecto**; no se usa `dangerouslySetInnerHTML`.
- ⚠ Hay que **añadir el origin del panel a `CORS_ALLOWED_ORIGINS`** de los microservicios
  (auth, payment, access, fitness), p. ej. `https://admin.gympro.com` (o `http://localhost:5173` en dev).

## Sistema de diseño (TailAdmin Pro)
UI estilo TailAdmin: canvas `gray-50`, sidebar/topbar blancos, primario morado (`brand`/`indigo`),
tipografía **Inter**, cards `rounded-2xl` con sombra suave, badges "soft" y **modo oscuro** (toggle en el topbar, clase `dark` en `<html>`, persistido).

Piezas reutilizables:
- `components/ui/` → `Card`/`CardHeader`, `KPIStat`, `StatusBadge`, `PillFilter`.
- `components/charts/` → `RevenueAreaChart` (área MRR con gradiente), `AltasBajasBarChart` (barras radio superior), `RetentionDonut` (gauge). Usan **Recharts**.
- `components/icons.tsx` → iconos outline inline (sin dependencia de librería de iconos).

> **Nueva dependencia:** `recharts`. Ejecuta `npm install` antes de `npm run dev`/`build`.

### Acceso por rol (importante)
Los **ingresos y la gestión financiera se reservan al rol `admin`**. La recepción (`staff`) —que
opera cobros en terminal y genera tickets— **no** ve el dashboard financiero, suscripciones ni ofertas:
solo Miembros. El gating está en `App.tsx` (`Protected adminOnly`) + `lib/roles.ts` (`isAdmin`), y el
sidebar oculta los ítems `adminOnly` para no-admins. Un `staff` que navegue a `/`, `/finance` o
`/offers` es redirigido a `/members`.

> Datos: los gráficos consumen `GET /admin/finance/series?months=36` (serie mensual REAL:
> ingresos del ledger `historial_pagos`, altas/bajas de `suscripciones`) y agregan por periodo
> en cliente (`lib/financeSeries.ts`). Si ese endpoint no está disponible, caen a una serie de
> muestra (`lib/financeSample.ts`) marcada con el chip "datos de muestra". Los KPIs y la dona de
> cartera usan `GET /admin/finance/summary`.
> La serie de ingresos incluye **presencial** (efectivo/terminal) y **Stripe online**: el webhook
> `invoice.paid` asienta cada cobro en `historial_pagos` (migración 008, idempotente por
> `stripe_event_id`).

## Endpoints backend a crear (ADMIN, protegidos con requiredRoles: STAFF_ROLES)
El panel ya consume estas rutas; algunas aún no existen en los microservicios:

### auth-service (`/api/v1/auth`)
- `GET  /me` — (ya existe) perfil del usuario autenticado.
- `GET  /admin/members?search=` — lista de miembros (paginable).
- `PATCH /admin/members/:id` — `{ activo }` suspender/reactivar.

### payment-service (`/api/v1`)
- `GET  /admin/finance/summary` — `{ ingresosMes, moneda, suscripcionesActivas, suscripcionesPastDue, altasMes, bajasMes }`.
- `GET  /admin/finance/series?months=` — (ya existe) serie mensual `{ moneda, ingresos[], altasBajas[] }` para los gráficos.
- `GET  /admin/subscriptions?estado=` — lista de suscripciones (join con email del socio).
- `POST /admin/subscriptions/:id/cancel` — cancela (y refleja en Stripe si aplica).
- `POST /admin/subscriptions/:id/extend` — `{ dias }` cortesía / extensión.
- `GET  /admin/offers` · `POST /admin/offers` · `PATCH /admin/offers/:id` — CRUD de ofertas/cupones.

Todas deben ir detrás de `createJwtVerifyMiddleware({ redisClient, requiredRoles: env.STAFF_ROLES })`
y usar `service_role` para leer/escribir en Supabase (el RLS deny-all bloquea el acceso directo).
Mientras un endpoint no exista, la página muestra un aviso ámbar "Endpoint no disponible" — no crashea.
