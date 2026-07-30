# Informe de divergencias DDL ↔ código + reconciliación canónica

La BD de producción estaba **vacía**; al bootstrapear desde el DDL del repo (`01`/`02`
+ migraciones) y migrar los servicios a mínimo privilegio (pg valida tipos de verdad),
salieron desajustes **profundos** entre el DDL del repo y lo que el código realmente
usa. Conclusión: **producción nunca corrió con el DDL del repo**; el `01`/`02` es un
diseño viejo/abandonado. Este informe fija la reconciliación (código = fuente de verdad).

## Leyenda de estado
- ✅ **OK**: DDL coincide con el código.
- 🩹 **parche**: se corrigió vía migración (010/012/013).
- 🔴 **divergente**: el DDL difiere por completo → recreado a código.

## auth_service_db
| Tabla | Estado | Detalle |
|---|---|---|
| usuarios | ✅ / 🩹 | 01 coincide con SAFE_COLUMNS; + `pin_terminal` (003), `refresh_token_expires_at` (fechada), `push_token`/`objetivo_fitness`/`lesiones` (010) |
| refresh_tokens | ✅ | 01 + fechada `refresh_tokens_table_families` coinciden (familias, reuse) |
| tokens_password_reset | ✅ | `usuario_id, token_hash, usado, expira_en` coinciden |
| passkey_credentials | 🩹 | **no existía en el DDL**; autorizada en 010 desde passkeyModel.js |

## access_service_db  ← el más divergente
| Tabla | Estado | Detalle |
|---|---|---|
| historial_accesos | 🔴→🩹 | DDL: `resultado`(enum), `tipo_acceso`, `qr_jti`, `dispositivo_id`… · Código (log): `fecha_hora`, `acceso_concedido`, `razon_rechazo`, `metodo_acceso`, `token_codigo`. **Solo `usuario_id` coincidía.** → recreada en **013** |
| tickets_visitas | 🔴→🩹 | DDL: `token_codigo`, `estado`(enum ES disponible/canjeado), `canjeado_en` · Código: `codigo_ticket`(unique), `estado` 'active'/'used', `usado_at`/`usado_en`, `creado_at`. → recreada en **013** |
| qr_nonces_consumidos | 🩹 | compatible (`nonce` PK, `usuario_id`, `turnstile_id`, `consumido_en`); recreada en 013 para garantizar `nonce` PK |
| zk_device_commands | 🩹 | **no existía**; autorizada en 010 desde zkAdmsService.js |

> ⚠ **Bug cruzado corregido:** el worker de payment leía `historial_accesos.creado_en`,
> pero la columna real (código de access) es **`fecha_hora`**. Corregido en growthRetentionWorker.js.

## payment_service_db
| Tabla | Estado | Detalle |
|---|---|---|
| suscripciones | 🩹 | faltaban `monto`, `moneda`, `ultimo_pago_en`, `proximo_pago_en`, `cancelado_en`, `razon_*`, `notificado_*` (010); enum `estado` en español → +inglés (012) |
| historial_pagos | ✅ | 004 + 008 coinciden (inglés: `completed`) |
| ofertas | ✅ | 007 coincide |
| webhook_events_procesados | ✅ | 006 coincide (PK `event_id`) |
| pagos / planes | ✅ (indirecto) | los usa la RPC `registrar_pago_efectivo` (SECURITY DEFINER), no los modelos directamente |

**Enums payment:** `estado_suscripcion_enum` y `metodo_pago_enum` estaban en español;
el código usa inglés → valores añadidos en **012**.

**Funciones** (SECURITY DEFINER, correctas, se conservan): `registrar_pago_efectivo`,
`increment_offer_usage`, `assign_pin_terminal`, triggers `set_updated_at`, `deny_ledger_mutation`.

## fitness_service_db
| Tabla | Estado | Detalle |
|---|---|---|
| catalogo_alimentos | ✅ | 02 coincide |
| ejercicios, rutinas, rutina_ejercicios, progreso_fisico | 🩹 | el código usa estos nombres; el DDL (02) tiene huérfanos `catalogo_ejercicios`/`rutinas_usuario`/`registros_nutricion`. Autorizadas en 010 |
| (huérfanos de 02) | ⚪ | `catalogo_ejercicios`, `rutinas_usuario`, `registros_nutricion` → NO crear / dropear (paso opcional del bootstrap) |

## ai_service_db
Sin tablas (ai-service es apátrida: historial del cliente + caché Redis).

## Enums de perfil (sexo_biologico, nivel_actividad) — SIN conflicto de backend
A diferencia de `estado_suscripcion`/`metodo_pago` (donde el CÓDIGO escribía inglés → se
arregló en 012), estos dos son campos de perfil **pass-through**: `userModel.updateProfile`
escribe lo que manda el cliente y el backend **no hardcodea** ningún valor (0 ocurrencias
de `masculino`/`sedentario`/etc. en todo el repo) ni los valida. Por tanto **no requieren
fix de BD** — el enum en español es la única restricción y el backend no la contradice.
⚠ Verificación pendiente **del lado móvil**: la app Flutter debe enviar los valores del
enum (`masculino`/`femenino`/`no_especificado`; `sedentario`/`ligeramente_activo`/
`moderadamente_activo`/`muy_activo`/`extremadamente_activo`), o el UPDATE de perfil fallará.

---

## Cómo obtener el schema CANÓNICO (autoritativo)
En vez de re-escribir a mano ~600 líneas (riesgo de errores de tipo), lo más fiable es
**dumpear la BD ya reconciliada**, que es garantizadamente correcta:

1. Aplica en orden sobre una BD limpia: `bootstrap.sh` (01/02/003-008/010/012) + `011` (roles/wiring, tras 009) + **`013`**.
2. Genera el schema canónico:
   ```bash
   pg_dump "$DB_ADMIN_URL" --schema-only --no-owner --no-privileges \
     --schema=auth_service_db --schema=access_service_db \
     --schema=payment_service_db --schema=fitness_service_db \
     -f docs/database/schemas/CANONICAL_SCHEMA.sql
   ```
3. Commitea `CANONICAL_SCHEMA.sql` como **única fuente de verdad** y marca `01`/`02`
   como obsoletos (o bórralos), dejando las migraciones 003–013 como historia.

## Orden de aplicación actualizado
`00`(omitido) → `01` → `02` → `003`–`008` → fechadas → `010` → `012` → **`009`(roles)** → **`011`(wiring)** → **`013`**.

`013` va **DESPUÉS de 009** porque hace `GRANT ... TO svc_access/svc_payment` y crea sus
policies: recrea las tablas de access alineadas al código y re-establece los permisos que
el `DROP` se llevó (los que 009 había dado sobre las tablas viejas).
