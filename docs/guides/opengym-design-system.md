# Sistema de componentes "calm layout" (openGym → GymPro)

Adopta la **estructura de layout** de openGym (tarjetas neutras redondeadas, jerarquía
clara, rótulos en versalitas, números grandes, acentos usados con moderación) **sin
tocar la paleta de GymPro**. Los colores siguen siendo los tokens ya aplicados en
`app_colors.dart`; lo que cambia es el ritmo, la geometría y el uso del color.

> Regla de oro: openGym usa **verde = positivo/activo, ámbar = en curso, gris = neutro**.
> GymPro ya tiene esos roles → se mapean 1:1 a `accentEmerald`, `warning`, `textSecondary`.

## Base geométrica — `core/theme/app_spacing.dart`

Rejilla de 8pt (medio paso 4pt). Todo el kit consume estas constantes; no hay números
mágicos en los widgets.

| Token | px | Uso |
|---|---|---|
| `xs` | 4 | icono ↔ texto |
| `sm` | 8 | interior compacto |
| `md` | 12 | gap estándar entre elementos / entre tarjetas |
| `lg` | 16 | padding interior de tarjeta (`cardPadding`) |
| `xl` | 20 | margen de pantalla (`screenPadding`) |
| `xxl` | 24 | separación entre secciones |
| `xxxl` | 32 | separación entre bloques grandes |
| `radiusSm` 12 · `radiusMd` 16 · `radiusLg` 20 · `radiusXl` 28 | | chips · botones · tarjetas · hojas/nav |

`Gap.md()`, `Gap.lg(horizontal: true)`, etc. reemplazan a los `SizedBox` sueltos.

## Mapeo patrón openGym → componente GymPro

| Patrón en las capturas | Componente | Color (token) |
|---|---|---|
| Tarjeta gris redondeada con rótulo en versalitas | `SectionCard` | `surfaceOf` + `glassBorderOf`; título `textSecondary` |
| Acción de cabecera "＋ Log" / "Goal" | `CardAction` | `accentEmerald` (override por `color`) |
| Pills "Push Day" / "Rest" / "In Progress" | `PillTag` (`PillTone`) | active→`accentEmerald`, inProgress→`warning`, neutral→`textSecondary`, info→`accentCyan` |
| Cuadrícula 2×2 de métricas (número grande) | `StatTile` + `StatTileGrid` | número `textPrimary`; icono/rótulo `textSecondary` o acento |
| Tira MO–SU con hoy en verde + punto de actividad | `WeekDayStrip` (`WeekDay`) | hoy: círculo `accentEmerald`; actividad: punto `accentEmerald` |
| Banner "TODAY · Push Day — In Progress · Resume" | `InProgressBanner` | ámbar si `inProgress`, verde si listo |
| Nav inferior glass + FAB central de play | `NeonBottomNav` (`NavItem`) | activo `accentEmerald`; FAB gradiente esmeralda |

Todos viven en `lib/core/presentation/widgets/` y reutilizan primitivas ya existentes
del sistema (`GlassSurface`, `Pressable`/`PressHaptic`, `AppTypography`).

## Principios que hacen que se vea "calmado"

1. **Una superficie, un color.** El fondo dominante es neutro (`surfaceOf` #181818). El
   color de marca aparece **solo** en el elemento que importa (hoy, PR, CTA, activo). Se
   evita el glow por defecto — el glassmorphism intenso queda para overlays premium, no
   para el layout base.
2. **Jerarquía por tamaño, no por color.** Rótulo pequeño en versalitas (`captionOf`
   13px w600, `textSecondary`) sobre número grande (`numericLarge`, `textPrimary`). El
   ojo va al número, no a un degradado.
3. **Figuras tabulares** en toda cifra (`AppTypography` ya lo aplica) → los números no
   "bailan" al actualizarse en vivo (rest timer, peso, streak).
4. **Acento como estado, no como decoración.** `PillTone`/`InProgressBanner` eligen el
   color por *significado* (activo/en curso/neutro), así el mismo componente comunica
   estado sin texto extra.
5. **Rendimiento.** `NeonBottomNav` (BackdropFilter) va envuelto en `RepaintBoundary`;
   el feedback táctil usa el `Pressable` con muelle ya afinado. Sin listeners nuevos en
   el árbol de scroll.

## Cómo montar una pantalla con el kit (ejemplo: Home)

```dart
ListView(
  padding: AppSpacing.screenPadding,
  children: [
    const Gap.lg(),
    WeekDayStrip(days: week, onDayTap: ctrl.selectDay),
    const Gap.xl(),
    InProgressBanner(
      title: 'Push Day',
      subtitle: '6 ejercicios · 45 min',
      inProgress: session.hasDraft,
      onResume: ctrl.resume,
    ),
    const Gap.xl(),
    SectionCard(
      title: 'THIS WEEK',
      trailing: CardAction(label: 'Stats', icon: Icons.bar_chart_rounded, onTap: goStats),
      child: StatTileGrid(tiles: [
        StatTile(icon: Icons.fitness_center, label: 'Workouts', value: '4'),
        StatTile(icon: Icons.local_fire_department, label: 'Streak', value: '12', accent: warning),
        StatTile(icon: Icons.timer_outlined, label: 'This month', value: '18'),
        StatTile(icon: Icons.monitor_weight_outlined, label: 'Weight', value: '81.2'),
      ]),
    ),
  ],
)
```

`Scaffold(bottomNavigationBar: NeonBottomNav(...))` cierra el patrón con el FAB central
que lanza `GuidedWorkoutScreen`.

### ⚠️ Evitar que la barra tape el contenido (solape del FAB/nav)

`NeonBottomNav` es una barra casi sólida que se apoya abajo. Hay dos formas correctas de
montarla; ambas evitan que la última fila (p. ej. `LogSetRow`) quede tapada:

1. **Recomendado — como `bottomNavigationBar`:** el `Scaffold` reserva el espacio solo,
   el `body` nunca pasa por debajo.

   ```dart
   Scaffold(
     body: SafeArea(bottom: false, child: contenidoScrollable),
     bottomNavigationBar: NeonBottomNav(destinations: nav, currentIndex: i, ...),
   );
   ```

2. **Barra flotante (Stack, estilo Instagram):** el contenido SÍ pasa por debajo, así que
   el scroll debe reservar el alto de la barra en su `padding.bottom`:

   ```dart
   ListView(
     padding: EdgeInsets.only(
       left: AppSpacing.xl, right: AppSpacing.xl, top: AppSpacing.lg,
       bottom: NeonBottomNav.reservedSpace(context) + AppSpacing.md, // ← clave
     ),
     children: [...],
   );
   ```

   `NeonBottomNav.reservedSpace(context)` = alto del contenido (`contentHeight` 64) +
   safe-area inferior. El `+ AppSpacing.md` deja aire extra por si el FAB central
   sobresale. **Sin este padding, la fila de series se "cuela" detrás de la barra** (el
   bug de la captura).

## Componentes por pantalla (spec de las 5 pantallas)

Además de los primitivos anteriores, el spec de las 5 pantallas se cubre con estos
componentes. Todos mantienen los tokens de GymPro (verde=activo, ámbar=en curso,
gris=neutro); ninguno introduce colores nuevos.

**Home**
- `WeightTrackerCard` (`features/workout/.../weight_tracker_card.dart`) — valor grande
  (87 kg), badge "X kg to goal", chips `+ Log` / `Goal`, y `BodyWeightChart` con
  relleno verde graduado. Compone `SectionCard` + `CardAction`.

**Plan**
- `ScheduleListItem` — fila de día (Monday…) + `PillTag` de rutina (Push Day verde /
  Rest gris) + flecha `>`; borde verde tenue si es hoy.
- `RoutineCard` + `RoutinesHeader` — tarjeta con icono cuadrado verde, título y "N
  exercises"; cabecera con botón `+ New` verde.

**Session Active**
- `MediaPreviewCard` — preview del GIF/vídeo (recibe el `media` ya construido) con
  overlays glass `Minimize` y `Tap to pause`, y velo de pausa.
- `ExerciseMetaHeader` — título + info `(i)`, botones verdes `Superset previous/next`,
  y pills secundarias (`PillTone.info`) para músculo/equipo.
- `LogSetRow` — nº de serie + dos `QuantityStepper` (`WEIGHT (KG)` y `REPS`) + checkbox
  circular; la fila se tinta de verde al completarse.

**Stats**
- `SegmentedControl` (`core/.../segmented_control.dart`) — `1M / 3M / 1Y / All` con
  pastilla activa que se desliza (`easeOutCubic`).
- (ya existentes) `StatTileGrid` para el KPI 2×2, `ActivityHeatmapWidget` para el mapa.

**Exercises**
- `SearchField` (`core/.../search_field.dart`) — lupa + limpiar.
- `FilterChipRow` (`core/.../filter_chip_row.dart`) — fila deslizable; chip activo verde.
- `ExerciseListTile` — thumbnail + título + "músculo · equipo" + botón `+ Plan` verde
  (pasa a `Added` neutro cuando ya está en el plan).

Primitivo compartido nuevo: `QuantityStepper` (`core/.../quantity_stepper.dart`) —
control `-/valor/+` controlado, con figuras tabulares; lo usan `LogSetRow` y cualquier
input numérico futuro.

## Estado

| Componente | Archivo | Estado |
|---|---|---|
| Espaciado 8pt + `Gap` | `core/theme/app_spacing.dart` | ✅ |
| `PillTag` | `core/presentation/widgets/pill_tag.dart` | ✅ |
| `SectionCard` + `CardAction` | `.../section_card.dart` | ✅ |
| `StatTile` + `StatTileGrid` | `.../stat_tile.dart` | ✅ |
| `WeekDayStrip` | `.../week_day_strip.dart` | ✅ |
| `InProgressBanner` | `.../in_progress_banner.dart` | ✅ |
| `NeonBottomNav` | `.../neon_bottom_nav.dart` | ✅ |
| `QuantityStepper` | `.../quantity_stepper.dart` | ✅ |
| `SegmentedControl` | `.../segmented_control.dart` | ✅ |
| `SearchField` | `.../search_field.dart` | ✅ |
| `FilterChipRow` | `.../filter_chip_row.dart` | ✅ |
| `WeightTrackerCard` | `features/workout/.../weight_tracker_card.dart` | ✅ |
| `ScheduleListItem` | `.../schedule_list_item.dart` | ✅ |
| `RoutineCard` + `RoutinesHeader` | `.../routine_card.dart` | ✅ |
| `MediaPreviewCard` | `.../media_preview_card.dart` | ✅ |
| `ExerciseMetaHeader` | `.../exercise_meta_header.dart` | ✅ |
| `LogSetRow` | `.../log_set_row.dart` | ✅ |
| `ExerciseListTile` | `.../exercise_list_tile.dart` | ✅ |

**Pendiente (integración):** cablear estos componentes en las pantallas reales
(Home/Plan/Stats) y `flutter analyze` en tu máquina (aquí no hay SDK de Dart; balance de
sintaxis verificado). Los tokens de color **no se han modificado**.
```
