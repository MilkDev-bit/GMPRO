/// @file lib/core/theme/app_colors.dart
/// @description Paleta de colores estética con soporte completo y reactivo
/// para Dark Theme (Neon Sport Obsidian) y Light Theme (Sport High Contrast Glass).

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── 1. DARK THEME SEMANTIC PALETTE (Neon Sport Dark) ───────────────────────
  static const Color darkBackground = Color(0xFF121212);       // Fondo profundo neutro (menos violáceo)
  static const Color darkSurface = Color(0xFF181818);          // Tarjeta base (neutra, más aire)
  static const Color darkSurfaceElevated = Color(0xFF282828);  // Superficie superior (inputs / botones)
  static const Color darkSurfaceGlass = Color(0x2620203A);     // Glassmorphism translúcido oscuro (más sutil)
  static const Color darkGlassBorder = Color(0x1AFFFFFF);      // Borde de cristal muy sutil (hairline)
  static const Color darkTextPrimary = Color(0xFFF4F3F8);      // Blanco cálido (menos clínico que #FFF)
  static const Color darkTextSecondary = Color(0xFFA7A2C4);    // Gris frío legible (8.1:1)
  static const Color darkTextMuted = Color(0xFF7C769A);        // Gris apagado LEGIBLE (4.63:1, antes fallaba)

  // ── 2. LIGHT THEME SEMANTIC PALETTE (Sport High Contrast Glass) ────────────
  static const Color lightBackground = Color(0xFFF5F6FA);      // Fondo deportivo claro y limpio
  static const Color lightSurface = Color(0xFFFFFFFF);         // Tarjetas glassmorphism claras / blanco puro
  static const Color lightSurfaceElevated = Color(0xFFEDEDF5); // Superficie superior clara
  static const Color lightSurfaceGlass = Color(0xCCFFFFFF);    // Glassmorphism translúcido claro
  static const Color lightGlassBorder = Color(0x44000000);     // Borde sutil para cristal claro
  static const Color lightTextPrimary = Color(0xFF1A1D2E);     // Casi negro (≈15:1 sobre claro)
  static const Color lightTextSecondary = Color(0xFF4A4E69);   // Gris azulado medio (7.5:1)
  // WCAG 2.2 (1.4.3): el gris tenue anterior (#8E92B2) daba 2.82:1 → FALLA texto normal.
  // Profundizado a 4.53:1 conservando el matiz frío de la marca.
  static const Color lightTextMuted = Color(0xFF6C6F8C);       // Gris tenue legible (4.53:1)

  // ── 3. COLORES NEÓN VIBRANTES (Dark - Alta Luminancia) ─────────────────────
  // Neones DESATURADOS a un registro premium: siguen siendo de marca, pero menos
  // "chillones". Usar como acentos puntuales, no como relleno masivo.
  static const Color neonPink = Color(0xFF1DB954);         // Rosa premium (6.33:1 sobre oscuro)
  static const Color neonPinkLight = Color(0xFFFF7DAD);    // Resplandor rosa suave
  static const Color neonPurple = Color(0xFF8B3FE0);       // Púrpura sobrio (glow/relleno)
  static const Color neonViolet = Color(0xFF6C33D6);       // Violeta profundo
  // Púrpura texto/icono sobre oscuro: 8.1:1.
  static const Color neonPurpleText = Color(0xFFC98BFF);   // Púrpura texto-seguro (dark)
  static const Color neonCyan = Color(0xFF4FD6E0);         // Cian sereno (11.3:1 sobre oscuro)
  static const Color neonEmerald = Color(0xFF46E3A0);      // Verde esmeralda suave (12:1 sobre oscuro)

  // ── 4. COLORES NEÓN ADAPTADOS (Light - Contraste ≥ 4.5:1 sobre #F5F6FA) ─────
  static const Color lightNeonPink = Color(0xFFC51162);    // Magenta profundo (5.36:1)
  static const Color lightNeonPurple = Color(0xFF6200EA);  // Púrpura intenso (7.18:1)
  // El #00838F daba 4.19:1 (FALLA) y el #00C853 daba 2.07:1 (FALLA). Profundizados:
  static const Color lightNeonCyan = Color(0xFF00768A);    // Cian atlético (4.91:1)
  static const Color lightNeonEmerald = Color(0xFF0E7A3B); // Verde atlético (5.03:1)

  // ── 5. ESTADOS Y ALERTAS GLOBALES ──────────────────────────────────────────
  // Variantes neón para fondo OSCURO + variantes profundas para fondo CLARO
  // (los neón crudos fallan como texto sobre claro: error 3.29, warning 1.61,
  //  success 1.52, info 1.30). Usar los getters *Of para foreground adaptativo.
  static const Color error = Color(0xFFFF3366);            // Rojo neón (dark)
  static const Color success = Color(0xFF00E699);          // Verde neón (dark)
  static const Color warning = Color(0xFFFFB800);          // Ámbar neón (dark)
  static const Color info = Color(0xFF00F0FF);             // Cian neón (dark)
  static const Color lightError = Color(0xFFC62828);       // Rojo profundo (5.21:1)
  static const Color lightSuccess = Color(0xFF0E7A3B);     // Verde profundo (5.03:1)
  static const Color lightWarning = Color(0xFF8A5A00);     // Ámbar profundo (5.49:1)
  static const Color lightInfo = Color(0xFF00768A);        // Cian profundo (4.91:1)

  // ── 6. COMPATIBILIDAD ESTÁTICA LEGACY (Por defecto Dark) ───────────────────
  static const Color background = darkBackground;
  static const Color surface = darkSurface;
  static const Color surfaceElevated = darkSurfaceElevated;
  static const Color surfaceGlass = darkSurfaceGlass;
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color textMuted = darkTextMuted;

  // ── 7. GRADIENTES ESTILIZADOS ──────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [neonPurple, neonPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF17151F), Color(0xFF0E0D16)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Glow ambiental más contenido (acentos puntuales, no baño de color).
  static const RadialGradient backgroundGlow = RadialGradient(
    center: Alignment(-0.6, -0.4),
    radius: 1.2,
    colors: [Color(0x1A8B3FE0), Color(0x0DFF4D8F), Colors.transparent],
  );

  // ── 8. MÉTODOS Y EXTENSIONES ADAPTATIVAS REACTIVAS AL CONTEXTO ─────────────
  /// Determina si el tema actual en el contexto es oscuro (o si el OS está en dark mode).
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color backgroundOf(BuildContext context) => isDark(context) ? darkBackground : lightBackground;
  static Color surfaceOf(BuildContext context) => isDark(context) ? darkSurface : lightSurface;
  static Color surfaceElevatedOf(BuildContext context) => isDark(context) ? darkSurfaceElevated : lightSurfaceElevated;
  static Color surfaceGlassOf(BuildContext context) => isDark(context) ? darkSurfaceGlass : lightSurfaceGlass;
  static Color textPrimaryOf(BuildContext context) => isDark(context) ? darkTextPrimary : lightTextPrimary;
  static Color textSecondaryOf(BuildContext context) => isDark(context) ? darkTextSecondary : lightTextSecondary;
  static Color textMutedOf(BuildContext context) => isDark(context) ? darkTextMuted : lightTextMuted;
  static Color glassBorderOf(BuildContext context) => isDark(context) ? darkGlassBorder : lightGlassBorder;

  /// Retorna el color base para contenedores Glassmorphism (BackdropFilter) según el tema del OS.
  static Color glassColorOf(BuildContext context, {double? alpha}) {
    if (isDark(context)) {
      return const Color(0xFF151226).withValues(alpha: alpha ?? 0.42);
    } else {
      return Colors.white.withValues(alpha: alpha ?? 0.75);
    }
  }

  // ── 8.a NEÓN DECORATIVO (glow, bordes, rellenos) — NO garantiza 4.5:1 ──────
  static Color neonPinkOf(BuildContext context) => isDark(context) ? neonPink : lightNeonPink;
  static Color neonPurpleOf(BuildContext context) => isDark(context) ? neonPurple : lightNeonPurple;
  static Color neonCyanOf(BuildContext context) => isDark(context) ? neonCyan : lightNeonCyan;
  static Color neonEmeraldOf(BuildContext context) => isDark(context) ? neonEmerald : lightNeonEmerald;

  // ── 8.b ACENTOS DE TEXTO / ICONO (foreground) — SIEMPRE ≥ 4.5:1 ────────────
  // Usar SIEMPRE estos getters cuando un color de marca sea TEXTO o ICONO sobre
  // el fondo/superficie del tema. La única diferencia con los decorativos es el
  // púrpura (se aclara a neonPurpleText en oscuro para superar 4.5:1).
  static Color accentPinkOf(BuildContext context) => isDark(context) ? neonPink : lightNeonPink;
  static Color accentPurpleOf(BuildContext context) => isDark(context) ? neonPurpleText : lightNeonPurple;
  static Color accentCyanOf(BuildContext context) => isDark(context) ? neonCyan : lightNeonCyan;
  static Color accentEmeraldOf(BuildContext context) => isDark(context) ? neonEmerald : lightNeonEmerald;

  // ── 8.c ESTADOS COMO FOREGROUND (texto/icono) — SIEMPRE ≥ 4.5:1 ────────────
  static Color errorOf(BuildContext context)   => isDark(context) ? error   : lightError;
  static Color successOf(BuildContext context) => isDark(context) ? success : lightSuccess;
  static Color warningOf(BuildContext context) => isDark(context) ? warning : lightWarning;
  static Color infoOf(BuildContext context)    => isDark(context) ? info    : lightInfo;
}

/// Extensión de conveniencia sobre [BuildContext] para acceso rápido y limpio al tema reactivo.
extension AppColorsContext on BuildContext {
  bool get isDarkTheme => AppColors.isDark(this);
  Color get backgroundColor => AppColors.backgroundOf(this);
  Color get surfaceColor => AppColors.surfaceOf(this);
  Color get surfaceGlassColor => AppColors.surfaceGlassOf(this);
  Color get textPrimaryColor => AppColors.textPrimaryOf(this);
  Color get textSecondaryColor => AppColors.textSecondaryOf(this);
  Color get textMutedColor => AppColors.textMutedOf(this);
  Color get glassBorderColor => AppColors.glassBorderOf(this);
  Color glassColor({double? alpha}) => AppColors.glassColorOf(this, alpha: alpha);

  // Acentos de texto/icono con contraste garantizado (WCAG 2.2 ≥ 4.5:1).
  Color get accentPink => AppColors.accentPinkOf(this);
  Color get accentPurple => AppColors.accentPurpleOf(this);
  Color get accentCyan => AppColors.accentCyanOf(this);
  Color get accentEmerald => AppColors.accentEmeraldOf(this);
}
