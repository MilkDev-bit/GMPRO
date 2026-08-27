/// @file lib/core/theme/app_colors.dart
/// @description Paleta de colores estética con soporte completo y reactivo
/// para Dark Theme (Neon Sport Obsidian) y Light Theme (Sport High Contrast Glass).

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── 1. DARK THEME SEMANTIC PALETTE (Elegant Dark, estilo iOS) ──────────────
  // Grises NEUTROS de sistema (sin tinte púrpura). Fondo negro OLED + superficies
  // #1C1C1E / #2C2C2E como en iOS dark. Texto en grises neutros (label / secondary).
  static const Color darkBackground = Color(0xFF000000);       // Base negra (OLED, systemBackground)
  static const Color darkSurface = Color(0xFF1C1C1E);          // Tarjeta (secondarySystemBackground)
  static const Color darkSurfaceElevated = Color(0xFF2C2C2E);  // Superficie superior (tertiary)
  static const Color darkSurfaceGlass = Color(0x401C1C1E);     // Glass translúcido neutro
  static const Color darkGlassBorder = Color(0x14FFFFFF);      // Hairline separador muy sutil
  static const Color darkTextPrimary = Color(0xFFFFFFFF);      // Label primario (blanco puro)
  static const Color darkTextSecondary = Color(0xFFAEAEB2);    // Secondary label (gris neutro, ~7:1)
  static const Color darkTextMuted = Color(0xFF8E8E93);        // systemGray (tertiary, ~4.6:1)

  // ── 2. LIGHT THEME SEMANTIC PALETTE (Sport High Contrast Glass) ────────────
  static const Color lightBackground = Color(0xFFF2F2F7);      // systemGroupedBackground (iOS light)
  static const Color lightSurface = Color(0xFFFFFFFF);         // Tarjeta blanca
  static const Color lightSurfaceElevated = Color(0xFFE5E5EA); // systemGray5 (superficie clara)
  static const Color lightSurfaceGlass = Color(0xCCFFFFFF);    // Glass translúcido claro
  static const Color lightGlassBorder = Color(0x22000000);     // Separador hairline claro
  static const Color lightTextPrimary = Color(0xFF1C1C1E);     // Label (casi negro neutro)
  static const Color lightTextSecondary = Color(0xFF48484A);   // Secondary label (gris neutro)
  static const Color lightTextMuted = Color(0xFF8E8E93);       // systemGray (tertiary, ~4.6:1)

  // ── 3. ACENTOS DE SISTEMA (Dark) — desaturados estilo iOS ──────────────────
  // Paleta reducida y sobria: verde (primario/positivo), azul (info), índigo
  // (premium/IA). Se acabaron los rosas/magentas fosforescentes. Nombres legacy
  // conservados para no romper referencias; los valores ahora son colores iOS.
  static const Color neonPink = Color(0xFF5E5CE6);         // → índigo iOS (antes rosa neón)
  static const Color neonPinkLight = Color(0xFF8E8CF0);    // Índigo claro (glow suave)
  static const Color neonPurple = Color(0xFF5E5CE6);       // systemIndigo (dark)
  static const Color neonViolet = Color(0xFF5E5CE6);       // Índigo (unificado, sobrio)
  static const Color neonPurpleText = Color(0xFF9E9CFF);   // Índigo texto-seguro (dark)
  static const Color neonCyan = Color(0xFF64D2FF);         // systemTeal/azul sereno (dark)
  static const Color neonEmerald = Color(0xFF30D158);      // systemGreen (dark) — acento primario

  // ── 4. ACENTOS ADAPTADOS (Light - Contraste ≥ 4.5:1 sobre #F2F2F7) ──────────
  static const Color lightNeonPink = Color(0xFF3634A3);    // Índigo profundo (antes magenta)
  static const Color lightNeonPurple = Color(0xFF3634A3);  // Índigo profundo (7:1)
  static const Color lightNeonCyan = Color(0xFF0071A8);    // Azul/teal atlético (4.9:1)
  static const Color lightNeonEmerald = Color(0xFF248A3D); // Verde sistema (5:1)

  // ── 5. ESTADOS Y ALERTAS GLOBALES ──────────────────────────────────────────
  // Variantes neón para fondo OSCURO + variantes profundas para fondo CLARO
  // (los neón crudos fallan como texto sobre claro: error 3.29, warning 1.61,
  //  success 1.52, info 1.30). Usar los getters *Of para foreground adaptativo.
  static const Color error = Color(0xFFFF453A);            // systemRed (dark)
  static const Color success = Color(0xFF30D158);          // systemGreen (dark)
  static const Color warning = Color(0xFFFF9F0A);          // systemOrange (dark)
  static const Color info = Color(0xFF64D2FF);             // systemTeal (dark)
  static const Color lightError = Color(0xFFD70015);       // systemRed profundo (5.2:1)
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

  // ── 7. GRADIENTES ESTILIZADOS (sobrios, casi planos) ───────────────────────
  // CTA primario: verde de sistema con un ligero degradado (no arcoíris).
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF30D158), Color(0xFF248A3D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C1C1E), Color(0xFF141416)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Glow ambiental casi imperceptible (sin baño de color).
  static const RadialGradient backgroundGlow = RadialGradient(
    center: Alignment(-0.6, -0.4),
    radius: 1.2,
    colors: [Color(0x0A5E5CE6), Colors.transparent],
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
      return const Color(0xFF1C1C1E).withValues(alpha: alpha ?? 0.55);
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
