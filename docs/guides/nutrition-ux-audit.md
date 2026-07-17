# Auditoría UX — Componentes de dieta (Flutter)

**Rol:** Diseño de Interacción (IxD) + Flutter UX Premium.
**Alcance:** `food_search_modal.dart`, `macro_summary_dashboard.dart`, `meal_card.dart`
(+ `MealCardShimmer` en `premium_loading_overlay.dart`).
**Método:** revisión estática + verificación de balance sintáctico (sin SDK Flutter en
el entorno; no se ejecutó `flutter analyze`/simulador).

## Resumen ejecutivo

| # | Inconsistencia interactiva | Archivo | Severidad | Estado |
|---|---|---|---|---|
| U1 | `MealCardShimmer` no coincide con la tarjeta real (height fija 96 vs ~86, sin chevron, gaps distintos) → **layout jump** en el swap | `premium_loading_overlay.dart` | Alto | Corregido |
| U2 | El shimmer **nunca se usa**: la carga es un spinner a pantalla completa y las `MealCard` aparecen de golpe (hard cut, sin crossfade) | `nutrition_main_screen.dart` | Medio | Patch propuesto |
| U3 | El `Slider` de porción no tenía micro-escala amortiguada; háptica genérica (`selectionClick`) | `food_search_modal.dart` | Medio | Corregido |
| U4 | Botones de hidratación `+250/+500ml` con hitbox ~**36 px** de alto (< 44) | `macro_summary_dashboard.dart` | Alto (a11y) | Corregido |
| OK | Eliminar (swipe `Dismissible`) y cerrar/limpiar (`IconButton`) cumplen ≥44 | `meal_card.dart`, `food_search_modal.dart` | — | Conforme |

---

## 1. Layout Jumps (saltos de diseño)

### U1 (Alto) — El skeleton no era espejo de la tarjeta real
`MealCardShimmer` tenía `height: 96` fija, gap interno de 8 px y **sin** el espacio del
chevron. La cabecera colapsada real de `MealCard` mide ≈ **86 px** (`padding 20·2 +
avatar 46`), usa gap de 3 px entre nombre y hora, y reserva `SizedBox(10)` + chevron
de 26. Resultado: al reemplazar el shimmer por la tarjeta, cada fila **brincaba ~10 px**
y el contenido se recolocaba lateralmente (faltaba la columna del chevron).

**Fix:** se reescribió `MealCardShimmer` como **espejo exacto** del shell real —
mismo `borderRadius: 26`, `margin.bottom: 18`, `padding: 20`, avatar 46, dos barras de
texto con gap 3, columna derecha (kcal 19 + macros 11) y placeholder de chevron
(26 + `SizedBox(10)`). Sin `height` fija: la altura la define el avatar + padding,
igual que la cabecera colapsada. Swap sin reflow.

### U2 (Medio) — Falta de transición suave carga→contenido
Hoy `nutrition_main_screen.dart` (CASO B) muestra un `CircularProgressIndicator` a
pantalla completa y, al llegar el plan (CASO C), renderiza `NutritionPlanScreen`
directamente: **corte seco** entre dos `Scaffold`. `MealCardShimmer` está definido pero
**no se referencia en ningún lado**.

**Patch propuesto (drop-in)** — sustituir el spinner por una lista de skeletons que ya
ocupa el layout final, y cruzar con un `AnimatedSwitcher` (fade puro, sin cambio de
tamaño):

```dart
// en nutrition_main_screen.dart, reemplazando el cuerpo del CASO B / CASO C:
AnimatedSwitcher(
  duration: const Duration(milliseconds: 400),
  switchInCurve: Curves.easeOut,
  child: nutritionState.isLoading
      ? ListView(
          key: const ValueKey('skeleton'),
          padding: const EdgeInsets.all(20),
          children: const [
            SizedBox(height: 220),                 // placeholder del dashboard
            SizedBox(height: 20),
            MealCardShimmer(), MealCardShimmer(), MealCardShimmer(),
          ],
        )
      : NutritionPlanScreen(key: const ValueKey('content'), plan: nutritionState.plan!),
)
```

Con el shimmer ya alineado (U1), este cruce queda sin salto perceptible.

---

## 2. Feedback táctil y micro-interacciones (Slider de porción)

### U3 (Medio) — Recalculado sin sensación física
El `Slider` usaba `HapticFeedback.selectionClick()` y solo el número grande tenía un
`AnimatedSwitcher`; el bloque de macros no reaccionaba con "cuerpo".

**Fix aplicado** en `_buildPortionConfigurator`:
- **Háptica real por paso:** `HapticFeedback.lightImpact()` disparada **solo cuando
  cambia el gramaje redondeado** (evita spam de vibración durante el arrastre continuo;
  con `divisions: 49` cada paso son 10 g).
- **Micro-escala amortiguada:** un pulso `1.0 → 1.12 → 1.0` con `AnimatedScale`
  (`Curves.easeOutBack`, 140 ms, auto-reset a ~120 ms vía `Timer`) que envuelve tanto
  el número `${g}g` como la fila de macros, para que el recalculado "rebote" de forma
  física y orgánica.
- Los chips de preajuste (`50/100/…g`) reutilizan el mismo handler con
  `HapticFeedback.mediumImpact()` (gesto más deliberado).

```dart
void _applyPortion(double grams, {bool strongHaptic = false}) {
  if (grams.round() != _portionGrams.round()) {
    strongHaptic ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    _triggerValuePulse(); // 1.12 → (120ms) → 1.0
  }
  setState(() => _portionGrams = grams);
}
// Slider: onChanged: (v) => _applyPortion(v)
// AnimatedScale(scale: _valuePulse, curve: Curves.easeOutBack) { número + macros }
```

El `Timer` de reset se cancela en `dispose()` (sin fugas).

---

## 3. Accesibilidad y zonas calientes (Hitboxes ≥ 44×44)

### U4 (Alto — a11y) — Botones de hidratación por debajo del mínimo
`_WaterQuickButtonElastic` usaba `padding: symmetric(h14, v10)` con contenido de ~16 px
→ altura efectiva ≈ **36 px**, por debajo del mínimo de 44×44 px lógicos de Apple HIG.
Con dos botones separados solo 8 px, el riesgo de pulsar el contiguo era real.

**Fix aplicado:** `ConstrainedBox(minWidth: 44, minHeight: 44)` + `alignment: center`
alrededor del contenido, y `HitTestBehavior.opaque` en el `GestureDetector` para que
**toda** el área (incluido el padding) sea tappable.

### Elementos ya conformes (verificados)
- **Eliminar alimento:** es un `Dismissible` (swipe) cuyo objetivo es la fila completa
  (padding 14 + contenido ≈ 68 px de alto) → ≥44. Conforme. *(Si en el futuro se añade
  una afordancia de borrado por tap, debe envolverse igual en ≥44.)*
- **Cerrar modal / limpiar búsqueda:** `IconButton` → área táctil por defecto de 48 px.
  Conforme.
- **Chips de preajuste:** `ChoiceChip` usa `MaterialTapTargetSize.padded` (48 px) por
  defecto. Conforme.

---

## Archivos modificados

```
apps/gym_mobile_app/lib/core/presentation/widgets/premium_loading_overlay.dart   (U1)
apps/gym_mobile_app/lib/features/nutrition/presentation/widgets/food_search_modal.dart      (U3)
apps/gym_mobile_app/lib/features/nutrition/presentation/widgets/macro_summary_dashboard.dart (U4)
```

**Patch pendiente de decisión** (U2): wiring del `AnimatedSwitcher` + lista de skeletons
en `nutrition_main_screen.dart` (snippet arriba). No se aplicó para no tocar la lógica de
bloqueo/pago de esa pantalla sin tu visto bueno.

Verificación: balance sintáctico OK en los 3 archivos. Pendiente en entorno con Flutter:
`flutter analyze` + prueba en simulador (háptica real requiere dispositivo físico).
