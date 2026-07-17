# Auditoría técnica — `ai-service` y `fitness-service`

**Alcance:** lógica de interacción con LLMs, procesamiento de datos y consultas a
Supabase en los microservicios orientados a IA. Enfoque en los 4 ejes solicitados.
**Método:** revisión estática de código + pruebas en caliente de los validadores
propuestos (`node --check` + smoke tests). No hubo ejecución contra Railway/Supabase.

## Resumen ejecutivo (severidad)

| # | Hallazgo | Eje | Severidad |
|---|---|---|---|
| H1 | `ejercicio_id` de la IA nunca se valida contra el catálogo real (`ejercicios`) → FK rota al persistir rutinas | 1 | **Crítico** |
| H2 | El post-procesador borra músculos inválidos "en silencio"; puede dejar `musculos_primarios: []` y romper el mapa SVG; sin normalización ni fuzzy-match | 1 | Alto |
| H3 | Los `codigo_barras` alucinados se devuelven/persisten sin verificar contra `catalogo_alimentos` ni Open Food Facts | 2 | **Crítico** |
| H4 | Premisa del "mapa en caché que crece" **no aplica hoy** (el fallback es un `const` estático de 10 ítems). El riesgo real es otro (ver H5) | 2 | Informativo |
| H5 | `.or('nombre.ilike.%${query}%')` con `query` sin sanear → inyección de filtro PostgREST + escaneos costosos | 2 | Alto |
| H6 | Cero validación termodinámica: `calorias_meta` no cuadra con 4/4/9 ni con la suma de comidas | 3 | **Crítico** |
| H7 | System Prompt infla tokens: inyecta las 43 claves musculares + ejemplo JSON gigante en cada request; `slice(0,80)` es inútil (solo hay 43) | 4 | Alto |
| H8 | No se usan salidas estructuradas nativas (Gemini `responseSchema` / OpenAI `json_schema` strict) ni function calling | 4 | Alto |
| H9 | `AI_RECOMMENDATION_CACHE_TTL` existe pero el controller **no cachea** ni usa Redis → coste/latencia repetidos | 4 | Medio |
| H10 | El fallback de parseo (`{ nombre, rawContent }`) devuelve al frontend algo no renderizable; sin retry de reparación | 1/3 | Medio |

**Entregables de código (drop-in, aditivos, no rompen la lógica actual):**
`macroSanitizer.js`, `muscleValidator.js`, `foodReconciliationService.js`,
`structuredOutputSchemas.js` en `services/ai-service/src/services/`.

---

## Eje 1 — Robustez del mapeo anatómico y alucinaciones de ejercicios

### H1 (Crítico) — `ejercicio_id` sin reconciliar con el catálogo local

En `recommendationController.js:54-55` el prompt le pide a la IA un
`ejercicio_id` con formato `wger-<3 dígitos>` y hasta le autoriza **inventar**
el `video_url`. En el post-proceso (`:114-117`) solo se garantiza que el campo
**exista**, generando incluso un aleatorio `wger-${100..999}` si falta:

```js
if (!ej.ejercicio_id) ej.ejercicio_id = `wger-${Math.floor(Math.random()*900+100)}`;
```

Nunca se comprueba que ese ID exista en la tabla `ejercicios`/`catalogo_ejercicios`
(poblada desde wger). Consecuencia: si la rutina se guarda con
`routineModel.createRoutine()` (`routineModel.js:73-90`), los ítems de
`rutina_ejercicios.ejercicio_id` apuntan a ejercicios inexistentes → violación de
FK (o referencias colgantes si no hay FK), y el detalle del ejercicio
(`getExerciseById`) devolverá 404 en la app.

**Recomendación:** reconciliar contra el catálogo antes de responder/persistir.
Dos opciones combinables:
1. **En origen (preferido):** usar salida estructurada con `enum` de IDs válidos
   o *function calling* donde el modelo elija de una lista corta de candidatos que
   se le inyecta (los N ejercicios relevantes al objetivo/músculo, no los cientos).
2. **En post-proceso:** resolver por nombre (`ilike`) contra `ejercicios` y
   sustituir el `ejercicio_id` por el real; si no hay match, marcar el ejercicio
   como `no_catalogado: true` y no escribirlo en `rutina_ejercicios`.

### H2 (Alto) — Validador muscular demasiado laxo → **entregado `muscleValidator.js`**

El filtro actual (`_filterValidMuscles`, `:243-246`) hace `includes()` exacto y
**descarta en silencio**. Problemas: (a) no normaliza acentos/casing/espacios, así
que `"Tríceps Braquial"` o `"pectoral mayor"` se pierden; (b) puede dejar
`musculos_primarios: []`, violando la regla "≥1 músculo" del propio prompt y
dejando el mapa anatómico en blanco; (c) `enfoque_muscular` del día no se valida.

El módulo `muscleValidator.js` corrige esto con una cascada
exacto → etiqueta/sinónimo → **fuzzy (Levenshtein)** y garantiza invariantes.
Probado:

```
"triceps_braqual"      → triceps_braquial   (fuzzy)
"Tríceps Braquial"     → triceps_braquial   (exacto por etiqueta)
"pecho"                → pectoral_mayor_esternal (sinónimo)
"musculo_inventado_xyz"→ null (descartado y registrado)
```

`repairRoutinePlan(plan)` además: valida `enfoque_muscular`, si un ejercicio queda
sin primario lo **hereda** del enfoque del día (o lo descarta de forma controlada),
y verifica el formato de `ejercicio_id`. Devuelve un reporte de correcciones para
logging/observabilidad.

> **Nota factual:** el catálogo tiene **43** claves musculares, no 38. Por eso el
> `VALID_MUSCLE_KEYS.slice(0, 80)` del prompt (`:44`) nunca recorta nada.

### Integración sugerida (reemplaza el bloque `:105-120`)

```js
const { repairRoutinePlan } = require('../services/muscleValidator');
// ...tras JSON.parse(rawJsonString):
const { plan, corrections, droppedExercises } = repairRoutinePlan(planStructured);
if (corrections.length) logger.info('Rutina auto-corregida', { usuarioId, corrections, droppedExercises });
planStructured = plan;
```

---

## Eje 2 — Precisión nutricional e integración con Open Food Facts

### H3 (Crítico) — Barcodes alucinados sin verificación → **entregado `foodReconciliationService.js`**

`generateDietPlan` (`:139-236`) devuelve el JSON de la IA **tal cual**: los
`codigo_barras` (`:185,196`) nunca se contrastan contra `catalogo_alimentos` ni
contra Open Food Facts. `getFoodByBarcode` (`foodController.js:156-196`) devolverá
404 al escanear un código inventado, y si el plan se persiste, el usuario verá
productos que no existen.

El módulo `foodReconciliationService.js` resuelve cada alimento en cascada:
catálogo local (batch `.in()`) → **API pública de Open Food Facts** (`v2/product`,
timeout corto) → búsqueda por nombre → **degradación controlada** (si nada
resuelve: `codigo_barras=null`, `es_open_food_facts=false`,
`verificado='estimado_ia'`, conservando los macros como estimación etiquetada, no
como producto escaneable falso). Está desacoplado por inyección de dependencias
(`lookupByBarcodes`, `lookupByName`) para no acoplarse a la infra.

### H4 (Informativo) — Sobre el supuesto "memory leak del mapa en caché"

Revisado `foodController.js`: el fallback `FALLBACK_OPEN_FOOD_FACTS` (`:15-106`) es
un **array `const` de 10 elementos a nivel de módulo**. No crece en runtime, no se
hidrata dinámicamente y no hay ningún `Map`/`Set` acumulándose (`grep` de
`new Map`/`inMemory` en `fitness-service` → sin resultados). **Hoy no hay fuga de
memoria por ahí.** El riesgo aparecería solo si en el futuro se hidrata ese
fallback desde OFF/Supabase hacia un objeto sin límite. Patrón recomendado si se
implementa: **LRU acotado** (p. ej. `lru-cache` con `max` entradas + `ttl`),
nunca un objeto plano que crece sin cota en un contenedor de Railway de larga vida.

### H5 (Alto) — Inyección de filtro PostgREST en `searchFoods`

`foodController.js:121-123`:

```js
.or(`nombre.ilike.%${query}%,marca.ilike.%${query}%`)
```

`query` viene directo de `req.query.q` sin sanear. Un valor con comas o paréntesis
puede alterar la expresión `.or()` de PostgREST (fuga de filtros / errores) y los
`%...%` sin ancla fuerzan *sequential scans*. **Recomendación:** escapar comas/`%`
y validar longitud; idealmente usar `textSearch`/`ilike` parametrizado con índice
`pg_trgm` sobre `nombre`/`marca`.

---

## Eje 3 — Consistencia de macros y energía → **entregado `macroSanitizer.js`**

### H6 (Crítico) — Cero validación termodinámica

No existe ninguna comprobación de que
`calorias_meta ≈ 4·prot + 4·carb + 9·grasa`, ni por comida, ni que la suma de
comidas cuadre con la meta. La IA "redondea a ojo" y la app muestra totales
contradictorios.

`macroSanitizer.validateAndReconcile(plan)` aplica la ley de Atwater tomando los
**gramos como fuente de verdad** (la energía es función determinista de los
gramos) y **auto-corrige** antes de persistir. Probado:

```
plan: 180P/300C/75G, calorias_meta declarada = 3000
→ corrige calorias_meta a 2595   (180·4 + 300·4 + 75·9 = 2595)
→ corrige comida "desayuno": 999 → 535 kcal
```

Valida además cada alimento (`calorias_100g` vs sus macros, holgura 15% por
fibra/polialcoholes) y adjunta `_macros_check` con los totales calculados para que
el frontend muestre datos consistentes.

### Integración sugerida (antes del `res.json` de `generateDietPlan`)

```js
const macroSanitizer = require('../services/macroSanitizer');
const { plan, corrections, warnings } = macroSanitizer.validateAndReconcile(planStructured);
if (corrections.length || warnings.length) logger.info('Plan nutricional reconciliado', { usuarioId, corrections, warnings });
planStructured = plan;
// ...luego reconcilePlanFoods() para los barcodes (Eje 2)
```

---

## Eje 4 — Coste de tokens y latencia

### H7 (Alto) — System Prompt inflado

El prompt de rutina inyecta las 43 claves como texto (`:44,58`) **más** un ejemplo
JSON completo (`:60-85`) en **cada** petición; el de dieta embebe otro ejemplo
extenso con alimentos (`:163-209`). Todo esto son *input tokens* recurrentes que
disparan coste y TTFB en Railway.

### H8 (Alto) — Sin salida estructurada nativa → **entregado `structuredOutputSchemas.js`**

`llmClientService.generateStructuredContent` solo fija `responseMimeType:
'application/json'` (Gemini, `:214`) o `response_format: { type:'json_object' }`
(OpenAI, `:242`). Ninguno **restringe el esquema**. Migrar a:

- **Gemini:** `generationConfig.responseSchema = geminiRoutineSchema()` — usa
  `enum` de los 43 músculos, de modo que el modelo **no puede** emitir una clave
  inválida (elimina H2 en origen).
- **OpenAI:** `response_format = { type:'json_schema', json_schema: openaiRoutineSchema() }`
  con `strict:true` y `additionalProperties:false`.

Con el esquema declarado por API, se puede **eliminar del prompt** la lista de
músculos y el ejemplo JSON (quedando solo persona + reglas breves), reduciendo el
input de forma notable y bajando latencia. `structuredOutputSchemas.js` genera
ambos dialectos desde una sola fuente (43 claves en el enum, verificado).

### H9 (Medio) — Caché de recomendaciones sin usar

`AI_RECOMMENDATION_CACHE_TTL` (env, `:76`) está definido pero
`recommendationController` no instancia Redis ni cachea por
`(usuarioId, objetivo, nivel, dias)`. Peticiones idénticas re-invocan el modelo
Pro (caro). **Recomendación:** cachear el JSON final (ya validado) en Redis con esa
TTL y una clave hash de los parámetros.

### Otras optimizaciones

- **Few-shot mínimo:** con esquema estricto, 0–1 ejemplos bastan; hoy el ejemplo
  es más grande que la propia instrucción.
- **Candidatos acotados:** en vez de "todos los alimentos/músculos", inyectar solo
  el subconjunto relevante al objetivo (recuperado de Supabase) o dejar que el
  `enum` haga el trabajo.
- **`generateStructuredContent` (Gemini)** duplica `maxOutputTokens` (`:213`); si
  el plan excede, la respuesta se trunca → JSON inválido → fallback `rawContent`
  (H10). Con esquema + límite realista y un *retry* de reparación se evita.

---

## Cross-cutting / higiene

- **H10:** el `catch` de `JSON.parse` (`:100-103`, `:223-226`) devuelve
  `{ nombre, rawContent }`, que el frontend no puede renderizar como plan. Añadir
  un **reintento de reparación** (pedir al modelo que corrija a JSON válido) o
  responder 422 explícito en vez de un objeto ambiguo con 200.
- **Timeouts LLM:** las llamadas a Gemini/OpenAI en `generateStructuredContent` no
  tienen `AbortController`/timeout; una API colgada bloquea el worker de Railway.
- **Precedencia:** `history.slice(-env.AI_MAX_CONTEXT_MESSAGES || -20)`
  (`llmClientService.js:59,134`) se evalúa como `(-X) || -20`; funciona pero es
  frágil (si `X=0` cae a -20). Usar una variable intermedia clara.

## Archivos entregados

```
services/ai-service/src/services/macroSanitizer.js            (Eje 3)
services/ai-service/src/services/muscleValidator.js           (Eje 1)
services/ai-service/src/services/foodReconciliationService.js (Eje 2)
services/ai-service/src/services/structuredOutputSchemas.js   (Eje 1 + 4)
```

Son módulos **aditivos**: no modifican el comportamiento actual hasta que se
integren en `recommendationController.js` con los diffs indicados arriba. Todos
pasan `node --check` y las pruebas de lógica incluidas en esta auditoría.
