# Auditoría de accesibilidad cromática (WCAG 2.2) — Sistema de temas

**Alcance:** `lib/core/theme/app_colors.dart`, `app_theme.dart` y su uso en pantallas.
**Criterio clave:** WCAG 2.2 **1.4.3** (texto normal ≥ **4.5:1**) y **1.4.11**
(componentes UD/no-texto ≥ 3:1). **Método:** cálculo real de luminancia relativa y
ratios de contraste (script incluido en la auditoría). Sin SDK Flutter (no `flutter
analyze`).

## Resumen ejecutivo

| # | Hallazgo | Severidad | Estado |
|---|---|---|---|
| C1 | Neón crudo como **texto sobre fondo claro** falla 4.5:1 (cian 1.30, esmeralda 1.55, rosa 3.51) | **Alto** | Token + API corregidos |
| C2 | Tokens adaptados de luz insuficientes: `lightNeonCyan` 4.19, `lightNeonEmerald` **2.07**, `lightTextMuted` **2.82** | **Alto** | Corregidos |
| C3 | `neonPurple` (#9D00FF) como **texto sobre oscuro** = 3.71:1 (falla) | Medio | Añadido `neonPurpleText` (5.16) |
| C4 | `error/warning/success/info` neón fallan como texto en claro (3.29 / 1.61 / 1.52 / 1.30) | Medio | Variantes claras + getters |
| C5 | `ColorScheme.light.error` = `#FF3366` (3.29:1) | Medio | → `lightError` (5.21) |
| OK | Glassmorphism ya es adaptativo (`glassColorOf`, gradientes con `isDark`) | — | Confirmado |

Las mediciones se hicieron sobre el fondo claro real de la app (`#F5F6FA`) y sobre el
obsidiana oscuro (`#080614`).

---

## 1. Contraste en Modo Claro (Adaptive Light Theme)

### Diagnóstico (ratios medidos, texto sobre `#F5F6FA`)

| Token | Antes | Ratio | Después | Ratio |
|---|---|---|---|---|
| Cian de marca (texto) | `neonCyan #00F0FF` | **1.30** ✗ | `lightNeonCyan #00768A` | **4.91** ✓ |
| Esmeralda (texto) | `neonEmerald #00E676` | **1.55** ✗ | `lightNeonEmerald #0E7A3B` | **5.03** ✓ |
| Rosa/magenta | `neonPink #FF007A` | **3.51** ✗ | `lightNeonPink #C51162` | **5.36** ✓ |
| `lightNeonCyan` previo | `#00838F` | **4.19** ✗ | `#00768A` | **4.91** ✓ |
| `lightNeonEmerald` previo | `#00C853` | **2.07** ✗ | `#0E7A3B` | **5.03** ✓ |
| `lightTextMuted` | `#8E92B2` | **2.82** ✗ | `#6C6F8C` | **4.53** ✓ |
| error (texto) | `#FF3366` | **3.29** ✗ | `lightError #C62828` | **5.21** ✓ |
| warning | `#FFB800` | **1.61** ✗ | `lightWarning #8A5A00` | **5.49** ✓ |
| success | `#00E699` | **1.52** ✗ | `lightSuccess #0E7A3B` | **5.03** ✓ |
| info | `#00F0FF` | **1.30** ✗ | `lightInfo #00768A` | **4.91** ✓ |

Todas las tonalidades profundizadas conservan el matiz deportivo (cian atlético, verde
performance, magenta) — solo bajan la luminancia lo justo para superar 4.5:1.

### Causa raíz — API que mezclaba "glow" con "texto"
El problema sistémico no era solo el valor, sino que **las pantallas usaban el neón
crudo** (`AppColors.neonCyan`, `AppColors.neonPink`, `AppColors.info`…) como color de
**texto/icono**. Esos valores están calibrados para brillar sobre oscuro; sobre claro
son ilegibles.

**Solución (variaciones semánticas completas):** se separan dos familias en
`app_colors.dart`:

- **Decorativo** (glow, bordes, rellenos, no requiere 4.5:1): `neon*Of(context)`.
- **Foreground** (texto/icono, **garantiza ≥ 4.5:1** en ambos modos):
  `accentPinkOf`, `accentPurpleOf`, `accentCyanOf`, `accentEmeraldOf` y
  `errorOf / warningOf / successOf / infoOf`. También como extensión de `BuildContext`
  (`context.accentCyan`, etc.).

```dart
// FOREGROUND (texto/icono) — SIEMPRE ≥ 4.5:1
static Color accentPurpleOf(BuildContext c) => isDark(c) ? neonPurpleText : lightNeonPurple;
static Color accentCyanOf(BuildContext c)   => isDark(c) ? neonCyan       : lightNeonCyan;
static Color infoOf(BuildContext c)         => isDark(c) ? info            : lightInfo;
```

### Migración aplicada (demostrativa) y pendiente
Se migró el **dashboard** (`macro_summary_dashboard.dart`, flagship adaptativo): labels,
`%`, colores de barras de macros e hidratación pasan a `accent*Of / infoOf`.

**Pendiente de migrar** (mismo patrón `AppColors.neonX` → `AppColors.accentXOf(context)`
solo donde el color sea **texto/icono**):
`food_search_modal.dart` (título, badges Carbos/Grasas), `home/.../macro_progress_card.dart`,
`qr_access/...`, `subscription/...`. *(Las pantallas de auth envuelven un `Theme` oscuro
forzado, así que su neón crudo es válido: siempre sobre obsidiana.)*

---

## 2. Consistencia de Cristal (Glassmorphism Light/Dark)

**Diagnóstico: el cristal ya es adaptativo.** `AppColors.glassColorOf(context)` devuelve
`#151226 @ 0.42` en oscuro y `blanco @ 0.75` en claro, y los tres componentes con
`BackdropFilter` (`meal_card`, `macro_summary_dashboard`, `food_search_modal`) ramifican
el gradiente/relleno con `AppColors.isDark(context)`. Resultado: cristal esmerilado
oscuro de noche, translúcido claro de día. **Sin ruptura.**

**Contraste de iconos sobre el cristal:** al migrar los iconos/acentos a `accent*Of`, se
garantiza que un icono cian/púrpura sobre el cristal **claro** (blanco @ 0.75 sobre
`#F5F6FA`) siga por encima de 4.5:1 — antes un icono `neonCyan` sobre ese cristal era
prácticamente invisible.

**Observación (no bloqueante):** dos overlays son **oscuros por diseño** aunque el SO
esté en claro — `_AiServiceOverlay` (`#080614 @ 0.78`) y `_GenericNeonSpinner`
(`AppColors.background`) en `premium_loading_overlay.dart`. Es una decisión estética
(carga cinematográfica). Si se desea que respeten el modo del SO, basta cambiar esos dos
rellenos por `context.glassColor()`.

---

## Archivos entregados

```
apps/gym_mobile_app/lib/core/theme/app_colors.dart                 (C1–C4: tokens + getters semánticos)
apps/gym_mobile_app/lib/core/theme/app_theme.dart                  (C5: ColorSchemes completos, error claro)
apps/gym_mobile_app/lib/features/nutrition/presentation/widgets/macro_summary_dashboard.dart  (migración demostrativa)
```

`ColorScheme` de ambos temas ahora expone slots semánticos completos (`tertiary/onTertiary`,
`onSurfaceVariant`, `surfaceContainerHighest`, `outline/outlineVariant`, `onError`) para que
los componentes Material tomen colores accesibles por defecto.

**Verificación:** ratios calculados con fórmula WCAG (todos ≥ 4.5:1 tras el cambio) y
balance sintáctico OK en los 3 archivos. Pendiente en entorno Flutter: `flutter analyze`
y un pase con el *Accessibility Inspector* / *Contrast* en simulador iOS y Android.
```
