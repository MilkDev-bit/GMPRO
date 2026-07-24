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

## Endpoints backend a crear (ADMIN, protegidos con requiredRoles: STAFF_ROLES)
El panel ya consume estas rutas; algunas aún no existen en los microservicios:

### auth-service (`/api/v1/auth`)
- `GET  /me` — (ya existe) perfil del usuario autenticado.
- `GET  /admin/members?search=` — lista de miembros (paginable).
- `PATCH /admin/members/:id` — `{ activo }` suspender/reactivar.

### payment-service (`/api/v1`)
- `GET  /admin/finance/summary` — `{ ingresosMes, moneda, suscripcionesActivas, suscripcionesPastDue, altasMes, bajasMes }`.
- `GET  /admin/subscriptions?estado=` — lista de suscripciones (join con email del socio).
- `POST /admin/subscriptions/:id/cancel` — cancela (y refleja en Stripe si aplica).
- `POST /admin/subscriptions/:id/extend` — `{ dias }` cortesía / extensión.
- `GET  /admin/offers` · `POST /admin/offers` · `PATCH /admin/offers/:id` — CRUD de ofertas/cupones.

Todas deben ir detrás de `createJwtVerifyMiddleware({ redisClient, requiredRoles: env.STAFF_ROLES })`
y usar `service_role` para leer/escribir en Supabase (el RLS deny-all bloquea el acceso directo).
Mientras un endpoint no exista, la página muestra un aviso ámbar "Endpoint no disponible" — no crashea.
