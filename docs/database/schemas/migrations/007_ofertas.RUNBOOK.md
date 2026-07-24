# Runbook — Migración 007: `ofertas` (cupones/descuentos)

Despliegue de la tabla `payment_service_db.ofertas` y la función atómica de canje
`increment_offer_usage`. Aplica a la instancia de Supabase/Postgres del
`payment-service`.

## Qué crea

| Objeto | Propósito |
|---|---|
| `payment_service_db.ofertas` | Cupones gestionados desde el panel admin. |
| `uq_ofertas_codigo` (índice único sobre `LOWER(codigo)`) | Un código no se repite (case-insensitive). |
| `idx_ofertas_activas` (parcial) | Búsquedas de ofertas activas. |
| Política RLS `deny_all_ofertas` | Deny-all: **solo `service_role`** (los microservicios) accede. |
| `increment_offer_usage(codigo)` | `UPDATE ... SET usos = usos + 1` atómico. Lo invoca el webhook al canjear. `SECURITY DEFINER` + `REVOKE FROM PUBLIC`. |

## Precondiciones

- Migraciones 003–006 ya aplicadas.
- El esquema `payment_service_db` existe y `uuid_generate_v4()` está disponible
  (extensión `uuid-ossp`, ya usada por migraciones previas).
- Tener a mano la **connection string** con rol de propietario/`postgres`
  (NO el `anon`/`service_role` de la API — el DDL se aplica por conexión SQL directa).

## Aplicación

### Opción A — Supabase Studio (SQL Editor)
1. Dashboard → **SQL Editor** → New query.
2. Pega el contenido de `007_ofertas.sql` y ejecuta (**Run**).
3. Verifica que no haya errores (ver sección Verificación).

### Opción B — psql / CLI
```bash
# Desde la raíz del repo. Usa la URL de conexión directa de Postgres (no el pooler
# si vas a correr DDL con funciones; el pooler en modo transaction no siempre lo admite).
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f docs/database/schemas/migrations/007_ofertas.sql
```
`ON_ERROR_STOP=1` aborta al primer error en lugar de dejar la migración a medias.

El script es **idempotente** en su mayor parte (`CREATE TABLE IF NOT EXISTS`,
`CREATE INDEX IF NOT EXISTS`, `DROP POLICY IF EXISTS`, `CREATE OR REPLACE FUNCTION`),
por lo que re-ejecutarlo no falla si ya se aplicó.

## Verificación (post-aplicación)

```sql
-- 1. La tabla existe con RLS habilitado
SELECT relrowsecurity
FROM   pg_class
WHERE  oid = 'payment_service_db.ofertas'::regclass;         -- espera: t

-- 2. La política deny-all está presente
SELECT polname, polcmd
FROM   pg_policy
WHERE  polrelid = 'payment_service_db.ofertas'::regclass;    -- espera: deny_all_ofertas | *

-- 3. El índice único case-insensitive existe
SELECT indexname FROM pg_indexes
WHERE  schemaname = 'payment_service_db' AND tablename = 'ofertas';
-- espera: uq_ofertas_codigo, idx_ofertas_activas

-- 4. La función de canje existe y es SECURITY DEFINER
SELECT proname, prosecdef
FROM   pg_proc
WHERE  proname = 'increment_offer_usage';                    -- espera: t (prosecdef)
```

Prueba funcional rápida (rollback con transacción, no deja datos):
```sql
BEGIN;
INSERT INTO payment_service_db.ofertas
  (nombre, codigo, tipo, valor, valido_desde, valido_hasta)
VALUES ('smoke', 'SMOKE-TEST', 'porcentaje', 10, NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day');

SELECT payment_service_db.increment_offer_usage('smoke-test');  -- espera: 1 (case-insensitive)
SELECT payment_service_db.increment_offer_usage('NO-EXISTE');   -- espera: NULL
ROLLBACK;
```

## Rollback

```sql
DROP FUNCTION IF EXISTS payment_service_db.increment_offer_usage(TEXT);
DROP TABLE    IF EXISTS payment_service_db.ofertas;   -- CASCADE si algún objeto depende
```
> ⚠️ `DROP TABLE` borra los cupones creados. Solo úsalo si la migración falló antes
> de que existieran datos reales. En producción con datos, prefiere corregir hacia
> adelante (nueva migración) en lugar de dropear.

## Post-despliegue (fuera de este SQL)

1. **Reinicia** `payment-service` para que tome `STRIPE_DEFAULT_CURRENCY` (usada en
   cupones `monto_fijo`). **Debe coincidir con la moneda de los `price` de Stripe**
   o Stripe rechaza el cupón (`amount_off` con currency distinta al precio).
2. **CORS**: añade el origin del panel a `CORS_ALLOWED_ORIGINS` en `auth-service` y
   `payment-service` (ver `.env.example` de cada uno) y reinícialos.
3. Verifica el flujo end-to-end: crear oferta en el panel → checkout con `offerCode`
   → confirmar en el webhook que `usos` incrementa.
