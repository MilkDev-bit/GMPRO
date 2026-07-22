# Dirección de arte — Elevación "Neon Sport Dark" a clase mundial

**Rol:** Director de Arte UI/UX + Flutter Senior. **Enfoque:** cuatro pilares
(cristal real, spring physics, tipografía/rejilla, háptica multimodal) con
**presupuesto de 120 FPS**. **Método:** primitivas reutilizables + aplicación al
componente insignia. Sin SDK Flutter en el entorno (no `flutter analyze`).

## Entregables (primitivas nuevas)

| Archivo | Rol |
|---|---|
| `core/presentation/widgets/glass_surface.dart` | Cristal premium con highlight specular |
| `core/presentation/widgets/pressable.dart` | Toque con SpringSimulation + háptica |
| `core/theme/app_typography.dart` | Cifras tabulares + display editorial |
| `features/nutrition/presentation/widgets/meal_card.dart` | Aplicación de las 3 primitivas |

---

## 1. Glassmorphism real (specular highlight)

**Diagnóstico:** los componentes usaban `ClipRRect + BackdropFilter + opacidad`, un
cristal "plano" sin refracción. Un panel de vidrio real tiene un **filo de luz** en el
borde superior-izquierdo y una sombra sutil en el inferior-derecho.

**Solución — `GlassSurface`:**
- Borde interior de **1px** pintado por `CustomPainter` con un `LinearGradient`
  blanco@`specularOpacity` (arriba-izq) → transparente (abajo-der), **más** una línea
  de sombra inferior tenue → efecto bisel.
- `blurSigma` afinado a **14** (antes 12): desenfoque orgánico que deja "leer" el fondo
  sin aplanarlo. Tinte adaptativo (`glassColorOf`) o gradiente de marca.
- Rendimiento: **1 BackdropFilter + 1 trazo** de borde, todo dentro de un
  `RepaintBoundary` que impide repintar el árbol detrás en cada frame.

```dart
GlassSurface(
  borderRadius: 26, blurSigma: 14, specularOpacity: 0.22,
  border: Border.all(color: accent.withValues(alpha: .45), width: 1.5),
  gradient: LinearGradient(colors: [...], begin: Alignment.topLeft, end: Alignment.bottomRight),
  child: ...,
)
```
> Nota: `dart:ui` no ofrece saturación en `BackdropFilter`; la "saturación" se aproxima
> con el tinte/gradiente de marca sobre el blur (no requiere un shader extra costoso).

---

## 2. Físicas de resorte (Spring Physics)

**Diagnóstico:** las interacciones usaban curvas estáticas (`Curves.easeIn/easeInOut`),
que se sienten mecánicas.

**Solución — `Pressable`:** al presionar comprime a **0.95** (90 ms), y al soltar
**regresa con `SpringSimulation`** (`SpringDescription(mass:1, stiffness:520,
damping:20)`) → rebote elegante y táctil, no un `Tween` lineal.
- Un solo `AnimationController.unbounded` por botón; `Transform.scale` en el `builder`
  con el hijo pasado como `child` (no se reconstruye) → apto para 120 FPS.
- En `meal_card`, además, la curva de expansión pasó de `Curves.easeInOut` a
  `Curves.easeOutCubic` (asentamiento más natural sin overshoot que recorte contenido).

```dart
Pressable(haptic: PressHaptic.medium, onTap: openSheet, child: ...)
```

Aplicar en las acciones principales pedidas: **registrar agua** (`_WaterQuickButtonElastic`
→ reemplazable por `Pressable`), **finalizar serie** (workout), **escanear QR** (qr card),
**agregar alimento** (ya migrado).

---

## 3. Jerarquía tipográfica y rejilla matemática

**Rejilla 8pt:** el layout ya respeta múltiplos de 8/4 (paddings 20/24, gaps
8/12/14/24/28/32). Se mantiene el sistema.

**Cifras sin "temblor":** los números de macros/kcal/cronómetros cambiaban de ancho al
pasar de `1` a `8` (fuentes proporcionales), produciendo micro-saltos. Se añadió
`AppTypography.tabularFigures` = `[FontFeature.tabularFigures(), FontFeature.slashedZero()]`
y estilos numéricos dedicados `numericHeroOf / numericLargeOf / numericMediumOf` (height
1.0, kerning ajustado). Aplicado al contador de kcal y a la línea P/C/G de `meal_card`.

**Titulares editoriales:** `displayLarge/Medium` ahora con `height ≈ 1.05` y kerning
negativo (`-0.6 / -0.4`) → titulares compactos y editoriales.

```dart
Text('$val kcal', style: AppTypography.numericLargeOf(context)
    .copyWith(color: accent, fontSize: 19, fontWeight: FontWeight.w900)),
```

---

## 4. Retroalimentación multimodal (háptica + visual)

`Pressable` **acopla** la háptica al gesto (`selection` por defecto, `light`/`medium`
configurable) con la micro-escala — un solo widget cubre el pilar completo. La háptica se
dispara en el `onTapDown`, **nunca en el hilo de dibujado**. Los botones migrados dejan de
llamar `HapticFeedback` manualmente (lo centraliza `Pressable`), evitando dobles vibraciones.

---

## Notas de rendimiento (120 FPS)

- `GlassSurface` envuelve el blur en `RepaintBoundary`; el highlight specular es estático
  (`shouldRepaint` solo ante cambios de radio/opacidad/tema).
- `Pressable` no reconstruye el hijo (se pasa como `child`); solo transforma escala.
- Las cifras tabulares evitan re-layout de ancho variable en contadores animados.
- Se conservó una única capa de blur por tarjeta (no se anidan BackdropFilters).

## Aplicación y adopción (estado)

| Componente | Cambio aplicado |
|---|---|
| `meal_card.dart` | `GlassSurface` (blur 14 + specular + borde acento) · `Pressable` en "Agregar Alimento" · kcal y P/C/G con cifras tabulares · `sizeCurve` → `easeOutCubic` |
| `home_dashboard_screen.dart` | Header sticky migrado a `GlassSurface` (blur progresivo con el scroll + specular 0.12) |
| `macro_summary_dashboard.dart` | Botones **+250/+500 ml** migrados a `Pressable` (spring + háptica media), eliminando su `AnimationController` con `easeInOut` · contador de kcal con `numericHeroOf` y ml con cifras tabulares |
| `dynamic_access_qr_card.dart` | Háptica media en la acción financiera primaria (checkout Stripe) |

**Nota sobre botones Material:** los `ElevatedButton` (p. ej. checkout de Stripe) **no** se
envuelven en `Pressable` — competirían en la *gesture arena* con el gesto propio del botón.
Para ellos se añade la háptica en `onPressed`; si se quiere también la micro-escala, hay que
sustituir el `ElevatedButton` por un `Container` dentro de `Pressable`.

**Pendiente de adoptar:** tarjetas de workout ("finalizar serie") y
`food_search_modal.dart` (la hoja ya tiene su propio pulso de escala + háptica del slider).

> La tarjeta QR **no** tiene botón de "escanear": el código lo lee el torniquete, por lo que
> su acción primaria real es el checkout — que es la que recibió la háptica.

**Verificación:** balance sintáctico OK en los 4 archivos. Pendiente en entorno Flutter:
`flutter analyze` + captura de *DevTools* (raster/UI thread) para confirmar 120 FPS y prueba
de háptica en dispositivo físico.
