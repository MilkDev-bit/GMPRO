# Wiring de los roles de mínimo privilegio (usar svc_* de verdad)

## Estado
009 creó los roles `svc_auth/svc_access/svc_payment/svc_fitness` (`NOBYPASSRLS`) con
GRANTs y policies. Pero **hoy son inertes**: los 5 servicios conectan con
`supabase-js` usando `SERVICE_ROLE_KEY`, que **bypassa RLS** y actúa como god-mode.
Este documento es el plan para que cada servicio opere con su rol.

## DECISIÓN (2026-07-29): enfoque híbrido
| Servicio | Enfoque | Motivo |
|----------|---------|--------|
| **payment** | **pg directo** | maneja dinero → máximo aislamiento (identidad a nivel de conexión) |
| **auth** | **pg directo** | credenciales/sesiones → máximo aislamiento |
| **fitness** | JWT scopeado | riesgo bajo; cambio mínimo (ya implementado) |
| **access** | JWT scopeado | riesgo medio; cambio mínimo |
| **ai** | — | apátrida, sin BD |

- **pg directo**: conexión Postgres con el usuario `svc_<servicio>` + su password (009).
  `ALTER ROLE svc_x SET search_path TO <schema>;` para no calificar cada tabla.
  Requiere reescribir los modelos de supabase-js a SQL parametrizado.
- **JWT scopeado**: `GRANT svc_x TO authenticator;` + `SUPABASE_JWT_SECRET`/`ANON_KEY`
  (ver enfoque B). Sin reescribir modelos.

## Dos enfoques

### A) `pg` directo (rechazado por ahora)
Conexión Postgres directa con el usuario `svc_*`. Implica **reescribir todos los
modelos** de la query builder de supabase-js a SQL crudo. Enorme y de alto riesgo.

### B) JWT con `role` scopeado (RECOMENDADO)
Mantener supabase-js/PostgREST, pero autenticar con un **JWT que lleva
`role: svc_<servicio>`** en vez del `SERVICE_ROLE_KEY`. PostgREST hace `SET ROLE
svc_<servicio>` y a partir de ahí aplican RLS + las policies de 009. **Cero cambios
en los modelos** — solo cambia el token en `config/database.js`.

## Prerrequisitos (enfoque B)
1. **Permitir a PostgREST cambiar a los roles** (SQL, aditivo y seguro):
   ```sql
   GRANT svc_auth, svc_access, svc_payment, svc_fitness TO authenticator;
   ```
   (`authenticator` es el rol de login de PostgREST en Supabase; sin esto no puede
   `SET ROLE` a los svc_*.)
2. **Nuevas variables por servicio**: `SUPABASE_JWT_SECRET` (secreto JWT del proyecto,
   en Supabase → Settings → API → JWT Secret) y `SUPABASE_ANON_KEY` (apikey).
   Hoy no están en los `.env`/Railway.

## Implementación (por servicio, en `config/database.js`)
Firmar un JWT de servicio con el claim `role` y pasarlo como `Authorization`:
```js
const jwt = require('jsonwebtoken');
function serviceToken() {
  return jwt.sign(
    { role: 'svc_payment', iss: 'gympro-payment-service' },
    env.SUPABASE_JWT_SECRET,
    { expiresIn: '1h' }               // rotar/re-firmar; o refrescar en cada boot
  );
}
supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  db:   { schema: env.SUPABASE_DB_SCHEMA },
  global: { headers: { Authorization: `Bearer ${serviceToken()}` } },
});
```
(El `role` del JWT debe coincidir con el rol del servicio: svc_auth, svc_access,
svc_payment, svc_fitness.)

## Riesgos y checklist de validación
Con RLS ya **aplicado** (no bypass), cualquier tabla/función que el servicio toque
sin policy/grant dará *permission denied*. Antes de activar por servicio:
- [ ] Confirmar que **cada** tabla en los `.from()` del servicio tiene su policy
      `svc_*` (009 cubre las auditadas; re-grep `.from()` por si algo nuevo).
- [ ] RPCs: las de pago son **SECURITY DEFINER** → corren como owner (OK). Verificar
      que svc_payment tenga EXECUTE (009 lo concede) y que no haya RPC INVOKER que
      toque tablas sin grant.
- [ ] Cruces de schema (payment→auth.usuarios, access→payment.suscripciones): con
      policy `svc_*_ro` (009) y USAGE del schema (009). Confirmado en 009.
- [ ] Probar **todos los endpoints** del servicio contra staging con el JWT scopeado.
- [ ] Rotación del JWT de servicio (exp corto + re-firma, o token de larga vida en
      secret manager con rotación).

## Rollout — PILOTO primero
1. Elegir **un** servicio de bajo riesgo (recomendado: **fitness** — sin dinero,
   RPCs simples) y aplicarlo en una rama de Supabase / staging.
2. Correr la suite + smoke de todos sus endpoints con el rol nuevo.
3. Si pasa, replicar en access → payment → auth (auth al final: más crítico).
4. Solo cuando los 5 usen su rol: **revocar** los privilegios de rutina de
   `service_role` y **rotar** su clave (dejarlo solo para administración).

## Nota
Este cambio hace que la app deje de usar god-mode. Es el objetivo de CLD-1, pero es
un cambio de producción real: hazlo por servicio, con pruebas, nunca los 5 de golpe.
