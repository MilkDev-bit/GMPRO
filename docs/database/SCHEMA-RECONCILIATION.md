# Reconciliación de schema — GymPro (2026-07-29)

## Contexto
La BD de producción (`ewomwhhcxespbdaiboka`) está **vacía**: nunca se aplicó el
schema de GymPro. Al preparar la migración 009 (roles) salió a la luz que el **DDL
del repo** y el **código de los servicios** están desincronizados, y que falta DDL.
Este documento fija la **fuente de verdad** y el trabajo para dejar un schema
correcto y consistente antes de inicializar la BD (y antes de 009).

## Fuente de verdad: el CÓDIGO
El DDL `02_fitness_service_db.sql` es de *first commit* (2026-07-17) y **el código de
fitness nunca referencia sus nombres** (`catalogo_ejercicios`, `rutinas_usuario`,
`registros_nutricion`). El código de los servicios (lo que corre y consulta) es
posterior y es lo que debe funcionar en runtime. → **El schema se alinea al código;
el DDL divergente se considera obsoleto.**

## Nombres de schema canónicos (los 5)
`auth_service_db`, `access_service_db`, `payment_service_db`, `fitness_service_db`,
`ai_service_db`. Coinciden con los **defaults del código** (`environment.js`) y con el
DDL de auth/access/payment.

> ⚠ **Bug de configuración:** los `.env` de fitness y ai traen
> `SUPABASE_DB_SCHEMA=fitness_schema` / `ai_schema` — valores **incorrectos**. Deben
> ser `fitness_service_db` / `ai_service_db` (en `.env` local **y** en Railway).

## Matriz código ↔ DDL

Leyenda: ✅ existe y coincide · 🔴 el código lo necesita y **no hay DDL** · ⚪ DDL huérfano (no lo usa el código)

### auth_service_db
| Tabla (la usa el código) | DDL | Estado |
|---|---|---|
| usuarios | 01 | ✅ |
| tokens_password_reset | 01 | ✅ |
| refresh_tokens | 01 | ✅ |
| passkey_credentials | **010_schema_gaps.sql** | ✅ autorizada (derivada de passkeyModel.js) |

### access_service_db
| Tabla | DDL | Estado |
|---|---|---|
| historial_accesos | 01 | ✅ |
| qr_nonces_consumidos | 005 | ✅ |
| tickets_visitas | 01 | ✅ |
| zk_device_commands | **010_schema_gaps.sql** | ✅ autorizada (derivada de zkAdmsService.js) |
| (cross-read) auth_service_db.usuarios | 01 | ✅ |
| (cross-read) payment_service_db.suscripciones | 01 | ✅ |

### payment_service_db
| Tabla | DDL | Estado |
|---|---|---|
| suscripciones | 01 | ✅ |
| historial_pagos | 004 | ✅ |
| ofertas | 007 | ✅ |
| webhook_events_procesados | 006 | ✅ |
| pagos | 01 | ⚪ (verificar uso vía funciones/modelos) |
| planes | 01/fechada | ⚪ (verificar uso) |
| (cross-read) auth_service_db.usuarios | 01 | ✅ |
| (cross-read) access_service_db.historial_accesos | 01 | ✅ |

### fitness_service_db  ← el más divergente
| Tabla (la usa el código) | DDL | Estado |
|---|---|---|
| catalogo_alimentos | 02 | ✅ |
| ejercicios | **010** | ✅ autorizada (exerciseModel.js) |
| rutinas | **010** | ✅ autorizada (routineModel.js) |
| progreso_fisico | **010** | ✅ autorizada (progressModel.js) |
| rutina_ejercicios | **010** | ✅ autorizada (routineModel.js) |
| — | catalogo_ejercicios | ⚪ huérfano → NO crear (recortar de 02) |
| — | rutinas_usuario | ⚪ huérfano → NO crear (recortar de 02) |
| — | registros_nutricion | ⚪ huérfano → NO crear (recortar de 02) |

### ai_service_db  ← NO se necesita (ai es apátrida)
ai-service **no persiste en Postgres**: el historial de chat llega del cliente
(`chatController`), la caché es Redis, y el health-check en `database.js` incluso
**tolera que la tabla no exista** (`error.code !== '42P01'`). `historial_chat` es
vestigial — nada lo escribe ni lo lee.

**Decisión:** no crear `ai_service_db` ni `historial_chat`, y **quitar ai (rol
`svc_ai`) de la 009**. Opcional: limpiar el health-check a `SELECT 1` para no
referenciar una tabla fantasma.

> Si en el futuro se quiere persistir el chat, se diseña `historial_chat`
> deliberadamente (con las columnas que se decidan) — no por reverse-engineering,
> porque hoy no hay uso del que derivarlo.

## Gaps a resolver (para que la app funcione)
DDL a **escribir** (derivando columnas/tipos de los modelos del código) → en `010_schema_gaps.sql`:
1. ✅ `auth_service_db.passkey_credentials` (WebAuthn) — HECHO (derivada de passkeyModel.js).
2. ✅ `access_service_db.zk_device_commands` (comandos ZKTeco) — HECHO (derivada de zkAdmsService.js).
3. ✅ `fitness_service_db`: `ejercicios`, `rutinas`, `progreso_fisico`, `rutina_ejercicios` — HECHO.
4. ❌ `ai_service_db` — NO se crea (ai es apátrida; ver arriba).

Config a **corregir**: `SUPABASE_DB_SCHEMA` de fitness (`fitness_schema`→`fitness_service_db`)
y ai (`ai_schema`→`ai_service_db`) en `.env` y en Railway.

DDL **obsoleto** a decidir (borrar o conservar): `catalogo_ejercicios`, `rutinas_usuario`,
`registros_nutricion` en `02_fitness_service_db.sql` (no los usa el código).

## Impacto en la migración 009 (roles)
009 debe **reescribirse** contra el schema canónico una vez exista:
- fitness: cambiar a `ejercicios`/`rutinas`/`progreso_fisico`/`rutina_ejercicios`
  (+ `catalogo_alimentos`), no los nombres actuales inventados.
- ai: `ai_service_db.historial_chat` — válido una vez creado el schema.
- El resto (auth/access/payment) ya cuadra salvo añadir `passkey_credentials` y
  `zk_device_commands` a los GRANT/policies.

## Orden propuesto
1. Autorizar y escribir el DDL faltante (gaps 1–4), por servicio, leyendo los modelos.
2. Consolidar un **bootstrap** ordenado (enums → schemas/tablas → migraciones) que
   deje la BD igual a lo que el código espera.
3. Corregir los `SUPABASE_DB_SCHEMA` de fitness/ai.
4. Aplicar el bootstrap a la BD (es prod-vacía: envolver en transacción, verificar).
5. Recién entonces: reescribir 009 contra el schema real y ejecutarlo.
