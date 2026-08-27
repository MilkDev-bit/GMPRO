# Port de openGym → GymPro

Adaptación de las funciones de [openGym](https://github.com/arvids-unavailable/openGym)
(AGPL) a GymPro. **Se reimplementan los algoritmos** (Epley, Greyskull LP, doble
progresión — conocimiento público), **no** se copia código de openGym.

Ubicación elegida: **Dart puro, offline-first**, igual que openGym pone su lógica en
funciones puras con tests (`frontend/src/lib/`). En GymPro viven en
`lib/features/workout/domain/training/` y se prueban con `flutter test`. Encaja con la
arquitectura Clean/Riverpod existente y no depende de red (el backend puede sincronizar
después). GymPro ya generaba planes por IA pero **no** calculaba el peso de la próxima
sesión ni el 1RM — este motor es justo esa pieza que faltaba.

## Estado por feature

| Feature openGym | Estado en GymPro |
|---|---|
| 📈 Reglas de progresión (lineal, Greyskull LP, doble) + deloads | ✅ **Entregado** (`progression.dart`) |
| 💪 1RM estimado (mejor serie ≤12 reps, nombra la serie) + calculadora | ✅ **Entregado** (`one_rep_max.dart`) |
| ⏱️ Ejercicios cronometrados (add-time) | ✅ regla `addTime` |
| 💪 Bodyweight en reps (+ techo → añade serie; con lastre sigue el peso) | ✅ regla `bodyweightReps` |
| ↔️ Reps por lado (objetivo en pares) | ✅ `perSide` |
| 🎯 Esfuerzo por serie (RIR/RPE, no afecta progresión) | ✅ campos en `SetLog` |
| 💪 Mapa muscular front/back | ✅ ya existe (`interactive_anatomy_map.dart`) |
| 🔑 Passkeys | ✅ ya existe (auth-service) |
| 🔔 Notificaciones (rest timer con app cerrada) | ✅ Live Activity iOS + FCM ya construidos |
| ▶️ Entrenamiento guiado (pre-carga pesos, PR, timer) | ✅ **Entregado** (Fase 2) |
| ⚖️ Peso corporal con línea de meta | ✅ **Entregado** (Fase 3) |
| 🟩 Heatmap de actividad | ✅ **Entregado** (Fase 3) |
| 🏋️ Librería de ejercicios + filtro equipo | ✅ Catálogo migrado a **free-exercise-db** (dominio público, el mismo dataset de openGym) vía `scripts/seed-free-exercise-db.js`; wger queda desactivado con `--replace` |
| ☀️ Pantalla despierta al entrenar | ✅ **Entregado** (`wakelock_plus`, Fase 2) |

## Fase 1 — Motor (entregado)

```
lib/features/workout/domain/training/
  set_log.dart        # SetLog, ExerciseSession, ProgressionConfig/Target, enums
  one_rep_max.dart    # epley1RM, weightForReps, estimateOneRepMax (≤12 reps)
  progression.dart    # nextTarget(cfg, history) → objetivo + "porqué"
test/features/workout/training/progression_test.dart   # 20+ casos
```

**API central (funciones puras):**

```dart
// El peso ya está bien cuando abre la sesión (openGym: "already right"):
final target = nextTarget(cfg: config, history: pastSessions);
//   target.weightKg / reps / timeSec  +  target.reason ("Completaste 3×5 → +2.5 kg")

// 1RM desde la mejor serie, nombrando cuál:
final est = estimateOneRepMax(session.sets);   // est.estimateKg, est.source
final w   = weightForReps(est!.estimateKg, 3); // calculadora para 3 reps
```

Invariantes garantizados (con test): reps falladas **nunca** suben la carga; N
estancamientos → deload %; bodyweight progresa en reps y, en el techo, añade serie;
1RM no adivina por encima de 12 reps.

## Fase 2 — Entrenamiento guiado (entregado)

```
lib/features/workout/domain/training/session_builder.dart   # plan IA → objetivo (puro, con test)
lib/features/workout/data/workout_history_store.dart         # historial local (SharedPreferences)
lib/features/workout/presentation/providers/guided_workout_provider.dart
lib/features/workout/presentation/screens/guided_workout_screen.dart
test/features/workout/training/session_builder_test.dart
```

- **`session_builder`** traduce el plan de IA (`WorkoutExercise`) a una
  `ProgressionConfig`: parsea "8-12" reps, infiere el tipo por nombre (plancha→timed,
  flexiones→bodyweight, press→weighted) y calcula el objetivo de hoy con `nextTarget`.
- **`guided_workout_provider`** lleva el ciclo: pre-carga los pesos desde el
  historial, registra serie a serie, **detecta PR** (1RM de la sesión vs. histórico),
  descansa con la **Isla Dinámica** (cuenta atrás nativa) y **mantiene la pantalla
  despierta** solo mientras entrenas. Al terminar, persiste cada ejercicio → la
  próxima sesión ya viene con los números correctos.
- **`guided_workout_screen`** es el runner (stepper peso/reps o tiempo, "porqué" del
  objetivo, badge de PR, rest timer, resumen final).

**Integración (1 línea en `workout_main_screen`):**
```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => GuidedWorkoutScreen(
    day: plan.dias[hoyIndex], objetivo: profile.objetivo, routineName: plan.dias[hoyIndex].dia),
));
```
Requiere `flutter pub get` (se añadieron `wakelock_plus` y `shared_preferences`).

> Nota: el historial usa `SharedPreferences` (JSON pequeño). Si prefieres que viva en
> la BD reactiva **Isar** que ya usa la app, la interfaz `WorkoutHistoryStore` permite
> cambiar la implementación sin tocar el provider ni el motor.

## Fase 3 — Cuerpo e historial (entregado)

```
lib/features/workout/domain/body/body_weight.dart        # serie de peso + dirección a la meta (puro)
lib/features/workout/domain/body/activity_heatmap.dart   # agregación por día → cuadrícula (puro)
lib/features/workout/data/body_weight_store.dart         # peso + meta (SharedPreferences)
lib/features/workout/data/activity_store.dart            # registro de sesiones (fecha + minutos)
lib/features/workout/presentation/providers/body_stats_provider.dart
lib/features/workout/presentation/widgets/body_weight_chart.dart       # fl_chart + línea de meta
lib/features/workout/presentation/widgets/activity_heatmap_widget.dart # CustomPainter estilo GitHub
lib/features/workout/presentation/screens/stats_screen.dart
test/features/workout/body/body_stats_test.dart          # 14 casos
```

- **Peso corporal:** `WeightSeries` clasifica cada cambio como *towardGoal* /
  *awayFromGoal* / *neutral* (funciona igual para cutting y bulk), con media móvil y
  "faltan X kg". El chart (`fl_chart`) dibuja la **línea de meta** punteada y colorea
  cada punto según acerque (esmeralda) o aleje (rosa).
- **Heatmap:** `buildYearHeatmap` agrega minutos por día en semanas × 7 días con 5
  niveles; el `CustomPainter` lo pinta en tonos neón dentro de un `RepaintBoundary`.
- **Cierre del bucle:** el runner guiado (Fase 2), al finalizar, escribe una
  `ActivityRecord` (fecha + duración real) → el heatmap se llena solo entrenando.

**Integración:** navegar a `StatsScreen()`. Sin dependencias nuevas (`fl_chart` y
`shared_preferences` ya estaban).

**Persistencia/sync.** El motor es agnóstico: hoy funciona con historial en memoria;
`fitness-service` puede persistir las sesiones (tabla `workout_sets`) y sincronizarlas
vía el mismo patrón M2M ya usado, sin tocar la lógica pura.

## Verificación

Balance sintáctico OK en los 4 archivos; aritmética de los casos validada
numéricamente (deloads, Epley, redondeo de barra). **Pendiente:** `flutter test` en tu
máquina (aquí no hay SDK de Dart) — los 20+ casos deberían pasar en verde.
