# Auditoría de performance UI (Flutter) — Mapa anatómico y overlays de carga

**Alcance:** `interactive_anatomy_map.dart` (CustomPainter + flip 3D) y
`premium_loading_overlay.dart` (shimmers, `_ScannerNeonPulse`, carrusel IA).
**Objetivo:** 60/120 FPS fijos. **Método:** revisión estática + verificación de
balance sintáctico (sin SDK Flutter en el entorno de auditoría; no se ejecutó
`flutter analyze`/DevTools).

## Resumen ejecutivo

| # | Cuello de botella | Archivo:línea | Severidad | Estado |
|---|---|---|---|---|
| P1 | `BackdropFilter` (blur pantalla completa) comparte capa de repintado con animaciones infinitas → se **re-blurea cada frame** | `premium_loading_overlay.dart:387-395` | **Alto** | Corregido |
| P2 | `CustomPainter` reconstruye la silueta + todos los paths musculares + `Paint` en **cada** `paint()` (60–120 fps) | `interactive_anatomy_map.dart:326-514` | **Alto** | Corregido |
| P3 | `_drawMuscleLabel` crea y hace `TextPainter.layout()` **por frame y por músculo** | `interactive_anatomy_map.dart:517-558` | Medio | Corregido |
| P4 | `_AiCorePulseIcon` reconstruye el `Icon` (const) cada frame; sin `const` ctor | `premium_loading_overlay.dart:464-529` | Bajo | Corregido |
| P5 | `_ViewToggleButton` usa el mismo icono para ambos estados (cosmético) | `interactive_anatomy_map.dart:906` | Cosmético | Corregido |

**Lo que ya estaba bien** (confirmado, sin cambios): todos los `AnimationController`
y el `Timer.periodic` se **liberan en `dispose()`**; `PremiumShimmer` está
correctamente aislado (`RepaintBoundary` + `AnimatedBuilder` con `child` estático);
el pulso muscular es **one-shot** (no un loop infinito), así que se estabiliza y
deja de repintar. **No hay memory leaks de controladores/timers.**

---

## Criterio 1 — Fugas de repintado (Repaint Leaks)

### P1 (Alto) — El escáner obliga a re-blurear toda la pantalla
En `_AiServiceOverlay`, dentro de un único `RepaintBoundary`, conviven:
un `BackdropFilter(blur 18)` a pantalla completa (**estático** pero carísimo), el
`_ScannerNeonPulse` (`repeat()` cada 2600 ms), el `_AiCorePulseIcon`
(`repeat(reverse)` cada 1800 ms) y el carrusel (`AnimatedSwitcher`).

Como los elementos animados **no** estaban aislados en su propia capa, cada frame de
la barra láser marcaba la capa como *dirty* y Flutter **recomponía el BackdropFilter**
(muestrear + desenfocar toda la pantalla) 60–120 veces por segundo, solo porque una
línea de 3 px se movió. Es el patrón clásico de *repaint leak* con blur.

**Fix:** aislar cada animación en su propio `RepaintBoundary` y envolver también el
`BackdropFilter`. Así el backdrop se pinta **una vez**, se cachea como capa
independiente y las animaciones repintan solo su franja:

```dart
RepaintBoundary(child: BackdropFilter(... )),      // capa estática, cacheada
const RepaintBoundary(child: _ScannerNeonPulse()),  // capa animada aislada
const RepaintBoundary(child: _AiCorePulseIcon()),   // capa animada aislada
SizedBox(height: 54, child: RepaintBoundary(child: AnimatedSwitcher(...))),
```

### Confirmación positiva del mapa anatómico
`InteractiveAnatomyMap` **ya** aísla correctamente: `RepaintBoundary` externo,
`AnimatedBuilder` que envuelve el `CustomPaint` en su propio `RepaintBoundary`, y el
fondo glass en otra capa. El `_highlightController` hace `forward()` **una sola vez**
(termina en `ConstantTween(0.65)`), por lo que **no** hay repintado perpetuo tras
asentarse — a pesar de que el doc-comment diga "loop". Sin fuga aquí.

---

## Criterio 2 — Liberación de recursos (Memory Leaks en UI)

**Sin hallazgos.** Verificado ciclo de vida por widget:

- `_InteractiveAnatomyMapState.dispose()` → `_highlightController.dispose()` +
  `_viewFlipController.dispose()`. ✔
- `_AiServiceOverlayState.dispose()` → `_timer?.cancel()`. ✔
- `_AiCorePulseIconState` / `_ScannerNeonPulseState` / `_PremiumShimmerState` →
  cada uno con su `AnimationController` liberado en `dispose()`. ✔
- `_LoginSuccessSplash` usa `Future.delayed` (no cancelable) pero protege con
  `if (mounted)` antes de invocar `onFinish`. ✔ (aceptable)

---

## Criterio 3 — Uso eficiente de constantes, Matrix4 y vectores SVG

### P2 (Alto) — Geometría reconstruida por frame
El `AnatomyBodyPainter.paint()` se ejecuta en cada frame de la animación. En cada
llamada:
- `_drawBodySilhouette` construía **todo** el `Path` del cuerpo (decenas de
  `moveTo/lineTo/close`) y **2 `Paint`** nuevos (`:327-334`).
- `_drawMuscleRegion` construía el `Path` del músculo y **2 `Paint`** por músculo.

Como el `CustomPaint` se dibuja siempre en `const Size(160, 320)` (⇒ `sx = sy = 1`),
**esa geometría es invariante entre frames**. Reconstruirla 60–120×/s es puro
desperdicio de CPU y presión sobre el GC.

**Fix:** memoización estática de la silueta (por región) y de los paths musculares
(por clave), más **`Paint` reutilizables** que solo mutan color/maskFilter:

```dart
static final Map<BodyRegion, Path> _silhouetteCache = {};
static final Map<String, Path> _muscleRegionCache = {};
static final Paint _muscleFill = Paint()..style = PaintingStyle.fill;
static final Paint _muscleGlow = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5;

// en paint():
final path = _silhouetteCache[region] ??= _computeSilhouettePath(sx, sy);
// ...
final path = _muscleRegionCache.putIfAbsent(muscleKey,
    () => _computeMuscleRegionPath(muscleKey, sx, sy) ?? Path());
_muscleFill.color = color.withValues(alpha: opacity * 0.6);
```

> Asunción documentada en el código: el canvas es de tamaño fijo. Si en el futuro se
> renderiza a otro tamaño, habría que incluir el `size` en la clave de caché.

### P3 (Medio) — `TextPainter.layout()` por frame
`_drawMuscleLabel` creaba un `TextPainter` y lo **layouteaba** en cada frame por cada
músculo primario — el `layout()` de texto es de las operaciones más caras en un
painter. La posición de los glifos **no** cambia; solo la opacidad anima.

**Fix:** cachear el `TextPainter` (layout una sola vez, con el color base) y aplicar
el fundido con una **capa de opacidad** (`saveLayer`) sin re-layout:

```dart
final textPainter = _labelCache.putIfAbsent(muscleKey, () => TextPainter(...)..layout(...));
final labelAlpha = (highlightOpacity * 0.95).clamp(0.0, 1.0);
if (labelAlpha >= 0.99) { /* pintar directo */ }
else { canvas.saveLayer(bgRect.inflate(6), Paint()..color = Color.fromRGBO(0,0,0,labelAlpha)); ... canvas.restore(); }
```

### Matrix4 del flip (correcto)
`Matrix4.identity()..setEntry(3,2,0.001)..rotateY(π·v)` se construye **dentro del
`AnimatedBuilder`**, no en el `build` del widget padre, y solo mientras dura el flip
(380 ms). La asignación por frame durante esa ventana breve es aceptable y no impacta
el estado de reposo. Sin cambios.

### P4/P5 (Bajo/cosmético)
- `_AiCorePulseIcon`: se añadió `const` ctor y se pasa el `Icon` const como `child`
  del `AnimatedBuilder` (no se reconstruye por frame).
- `_ViewToggleButton`: el estado "Posterior" mostraba el mismo icono que "Frontal";
  corregido a un icono distinto.

---

## Impacto esperado

- **Overlay IA:** el coste por frame pasa de "re-blur de pantalla completa + repintar
  todo" a "repintar solo la franja del láser/ícono" → elimina el mayor consumo de
  GPU/CPU del overlay y estabiliza 120 fps en dispositivos ProMotion.
- **Mapa anatómico:** durante el pulso/flip se elimina la reconstrucción de decenas
  de `Path`/`Paint` y el `TextPainter.layout()` por frame → menos jank y menos GC.

## Archivos modificados

```
apps/gym_mobile_app/lib/core/presentation/widgets/premium_loading_overlay.dart      (P1, P4)
apps/gym_mobile_app/lib/features/workout/presentation/widgets/interactive_anatomy_map.dart  (P2, P3, P5)
```

Verificación: balance sintáctico OK y sin referencias colgantes. **Pendiente en un
entorno con Flutter:** `flutter analyze`, y un pase de DevTools (timeline + "Track
widget repaints" / "Highlight repaints") para confirmar que el BackdropFilter deja de
aparecer en el repaint del escáner.
