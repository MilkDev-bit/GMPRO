# Remediación — Fase 1 (API / backend)

> Rama objetivo: `security/fase-1-api-backend`. Alcance: hallazgos de Fase 1 de
> API/backend del `audit-final-consolidado.md`. Metodología: baseline →
> corrección → validación → commit. Fecha: 2026-07-24.

## ⚠ Restricción del entorno (igual que en la rama infra)
El FS montado **bloquea el `unlink`** de `.git/*.lock`, por lo que **no se pudo
crear la rama ni commitear** en este entorno (los locks `index.lock`/`HEAD.lock`
huérfanos de la sesión anterior no se pueden eliminar). Todas las correcciones
**están aplicadas y validadas en el working tree**. Para empaquetarlas:
```bash
rm -f .git/index.lock .git/HEAD.lock
git checkout -b security/fase-1-api-backend
# luego los "Comando de commit" de cada sección.
```

## Estado

| # | Hallazgo | Estado | Commit |
|---|----------|--------|--------|
| 1 | API3 `select('*')` → columnas explícitas (fitness/access) | ⏳ **Pendiente de confirmación** (no se adivina) | — |
| 2 | API9 consolidar rutas no versionadas (deprecación no destructiva) | ✅ Corregido en árbol · ⏳ commit | pendiente |

---

## 1. API3 — Over-fetching (`select('*')`) · ⏳ Pendiente de confirmación

**Por qué NO se aplicó automáticamente (hallazgos que lo impiden con seguridad):**
1. **Los docs de esquema están desincronizados con la BD.** Los modelos consultan
   `.from('ejercicios')`, `.from('rutinas')`, `.from('progreso_fisico')`, pero
   `docs/database/schemas/02_fitness_service_db.sql` define `catalogo_ejercicios` y
   `rutinas_usuario` (y no define `progreso_fisico`). → **no tengo la lista real de
   columnas** desde el repo.
2. **Los clientes Flutter usan `fromJson` null-tolerante**: si omito una columna que
   el cliente lee, **no crashea** → la UI se degrada **en silencio** (regresión
   difícil de detectar en review).
3. **La respuesta de rutinas es un JOIN anidado de 3 tablas**
   (`rutinas(*, rutina_ejercicios(*, ejercicios(nombre, grupo_muscular)))`,
   `progressModel.js:95`), donde mapear cada `*` a las columnas correctas por tabla
   es propenso a error sin la BD real.

Adivinar columnas contra esquemas incorrectos rompería queries (columnas
inexistentes) o clientes (campos omitidos). Siguiendo la instrucción del encargo, se
**declara pendiente** con el análisis para completarlo con seguridad.

### Inventario de queries afectadas (fitness/access)

| Archivo:línea | Tabla | ¿Cliente? | Candidato de columnas (a confirmar) |
|---|---|---|---|
| `fitness exerciseModel.js:55` | ejercicios (catálogo) | Móvil (lista) | id + keys de `workout_entities.fromJson` de ejercicio |
| `fitness exerciseModel.js:111` | ejercicios | Móvil (detalle) | idem anterior |
| `fitness routineModel.js:64` | rutinas (fila creada) | Móvil | `id, usuario_id, nombre, descripcion, nivel, creado_at` (del `insert`) |
| `fitness progressModel.js:24` | progreso_fisico (lista) | Móvil | del `insert`: `id, usuario_id, peso_kg, porcentaje_grasa, masa_muscular_kg, medidas, notas, fecha_medicion` |
| `fitness progressModel.js:70` | progreso_fisico (fila creada) | Móvil | idem |
| `fitness progressModel.js:94-95` | progreso_fisico + rutinas(anidado) | Móvil (dashboard) | idem + mapa del join 3 tablas |
| `fitness foodController.js:129,178` | catalogo_alimentos | Móvil | keys de `nutrition_entities.fromJson` (schema SÍ existe: `02_…sql:168`) |
| `fitness internalController.js:67,93` | catalogo_alimentos | **M2M** (ai-service) | campos que consume `ai-service/foodReconciliationService` |
| `access accessModel.js:77,115,138,211` | historial_accesos / tickets_visitas | mixto (decisión + respuesta) | columnas de decisión + `id, estado, expira_en, usado_at` |

### Método de confirmación (rápido y seguro)
Como los clientes **ya reciben `select('*')` hoy**, la lista segura de columnas es
**exactamente los campos que su `fromJson` lee** (garantizado ⊆ columnas reales):

1. **Columnas reales por tabla** (staging):
   ```sql
   SELECT column_name FROM information_schema.columns
   WHERE table_schema='fitness_service_db' AND table_name='<tabla_real>' ORDER BY 1;
   ```
2. **Campos que consume el cliente** (ya extraídos para workout):
   `grep -oE "json\['[a-z_]+'\]" apps/gym_mobile_app/lib/features/**/entities/*.dart`
   (rutinas/ejercicios → `workout_entities.dart`; alimentos → `nutrition_entities.dart`;
   progreso → confirmar entity de progreso). Para M2M, revisar el parser del ai-service.
3. `SAFE_COLUMNS = unión de (1)∩(2)` por modelo, declarado como constante (patrón
   `SAFE_COLUMNS` de `subscriptionModel.js:19` / `userModel.js:19`), y sustituir cada
   `select('*')` por `select(SAFE_COLUMNS)`.
4. Verificar con un smoke test por endpoint (respuesta contiene todos los campos que
   el cliente parsea) antes de mergear.

### Plantilla de patch (por modelo, tras confirmar columnas)
```js
// arriba del modelo:
const SAFE_COLUMNS = 'id, usuario_id, nombre, descripcion, nivel, creado_at'; // ← CONFIRMAR
// en la query:
.select(SAFE_COLUMNS)   // en lugar de .select('*')
```

> **Recomendación adicional:** actualizar `docs/database/schemas/*` para que refleje
> los nombres de tabla reales (`ejercicios`/`rutinas`/`progreso_fisico`) — la
> desincronización actual es un riesgo por sí misma.

---

## 2. API9 — Consolidar rutas no versionadas · ✅ Corregido en árbol

**Enfoque no destructivo (requisito del encargo: no romper clientes publicados).**
Se confirmó que **clientes reales usan rutas legacy**:
- `reception-hardware-controller/node/reception_controller.js:350` llama
  `/validate-ticket` (**sin versión**).
- `reception-hardware-controller/node/cash_payment_client.js:28` usa
  `/api/v1/payments/cash-payment`.

Por eso **no se eliminó ninguna ruta**. Se añadió un middleware de **deprecación**
compartido y se aplicó a las variantes legacy, dejándolas **funcionales**.

**Corrección.**
- Nuevo `packages_shared/security/deprecation.js` → `createDeprecationNotice({ logger,
  successor, sunset })`: añade cabeceras `Deprecation: true`, `Sunset: <fecha>` (RFC
  8594) y `Link: <successor>; rel="successor-version"` (RFC 8288), y emite un log
  `event: DEPRECATED_ROUTE_USED` (con método/path/UA/ip) para **inventariar** qué
  clientes siguen usando la ruta vieja. No cambia el comportamiento.
- `access-service/src/main.js`: las variantes **sin versión** `/generate-qr`,
  `/create-ticket`, `/validate-ticket` quedan marcadas como deprecadas → sucesoras
  `/api/v1/...`. Las versionadas siguen limpias.
- `payment-service/src/main.js`: el alias `/api/v1/cash-payment` queda deprecado →
  sucesor `/api/v1/payments/cash-payment` (canónico: namespace de pagos y el que usa
  el hardware).
- `Sunset` objetivo: **2027-01-24** (~6 meses).

**Validación.**
- `node --check` OK en `deprecation.js`, `access/main.js`, `payment/main.js`.
- Suites: **payment 30 passed** (3 skipped), **access 8 passed** — sin regresiones.

**Plan de retiro gradual (para completar el retiro seguro):**
1. **Ahora–1 mes:** desplegar la deprecación; monitorear el log `DEPRECATED_ROUTE_USED`
   para cuantificar el tráfico legacy y qué clientes lo generan.
2. **1–3 meses:** migrar los clientes legacy a las rutas `/api/v1/...`:
   - `reception_controller.js:350` → usar el prefijo versionado (`/api/v1/validate-ticket`).
   - `cash_payment_client.js:28` → mantener `/api/v1/payments/cash-payment` (ya canónico).
   - Verificar que el móvil no dependa de rutas sin versión.
3. **Tras `Sunset` (2027-01-24) y con tráfico legacy ≈ 0:** eliminar las rutas legacy
   en un release mayor, anunciado en el changelog.

**Comando de commit:**
```bash
git add packages_shared/security/deprecation.js \
        services/access-service/src/main.js \
        services/payment-service/src/main.js
git commit -m "feat(sec): API9 deprecate unversioned/duplicate routes (non-breaking, RFC 8594 Sunset)"
```

---

## Resumen de validación

| Hallazgo | Validación | Resultado |
|----------|-----------|-----------|
| API3 | Análisis de esquema vs. modelos vs. parsers cliente | Pendiente: schema doc desincronizado + clientes null-tolerant → no adivinar ✅ (decisión) |
| API9 | `node --check` + `jest` access & payment | deprecation OK; 30 + 8 tests en verde ✅ |

## Pendientes declarados
- **API3**: confirmar columnas reales por tabla en staging (`information_schema`) +
  campos consumidos por cliente/M2M, luego aplicar `SAFE_COLUMNS` (plantilla arriba).
- **Retiro** de rutas legacy tras la ventana de `Sunset` (plan arriba).
- **Commits**: pendientes por la restricción de `.git/*.lock` del entorno.
