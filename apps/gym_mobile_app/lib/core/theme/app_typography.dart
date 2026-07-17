/// @file lib/core/theme/app_typography.dart
/// @description Estilos tipográficos modernos usando Google Fonts (Outfit e Inter)
/// con soporte adaptativo completo para Dark Theme y Light Theme.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  // Cifras tabulares + cero cortado: los dígitos ocupan el MISMO ancho, evitando
  // el "temblor" horizontal cuando cambian valores (macros, cronómetros, kcal).
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  // ── 1. ESTILOS LEGACY ESTÁTICOS (Por defecto Dark) ─────────────────────────
  // Titulares editoriales: interlineado compacto (height ≈ 1.05) + kerning negativo.
  static TextStyle get displayLarge => GoogleFonts.outfit(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: AppColors.darkTextPrimary,
        letterSpacing: -0.6,
        height: 1.05,
      );

  static TextStyle get displayMedium => GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
        letterSpacing: -0.4,
        height: 1.06,
      );

  static TextStyle get titleLarge => GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.darkTextPrimary,
      );

  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.darkTextSecondary,
        height: 1.5,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.darkTextSecondary,
        height: 1.4,
      );

  static TextStyle get buttonLabel => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
        letterSpacing: 0.5,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.darkTextMuted,
      );

  // ── 1.b CIFRAS GRANDES (macros / cronómetros) — tabular, sin temblor ───────
  /// Número "héroe" (44pt) para contadores de macros/kcal. Color adaptativo.
  static TextStyle numericHeroOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 44,
        fontWeight: FontWeight.w900,
        height: 1.0,
        letterSpacing: -1.0,
        color: AppColors.textPrimaryOf(context),
        fontFeatures: tabularFigures,
      );

  /// Número mediano (22pt) para kcal por tarjeta, series, etc.
  static TextStyle numericLargeOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -0.5,
        color: AppColors.textPrimaryOf(context),
        fontFeatures: tabularFigures,
      );

  /// Etiqueta numérica compacta (P/C/G, ml, etc.).
  static TextStyle numericMediumOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: 0.0,
        color: AppColors.textSecondaryOf(context),
        fontFeatures: tabularFigures,
      );

  // ── 2. INSTANCIAS DE TEXT THEME PARA THEME DATA ────────────────────────────
  /// TextTheme completo para el tema oscuro (Dark Theme)
  static TextTheme get darkTextTheme => TextTheme(
        displayLarge: GoogleFonts.outfit(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.darkTextPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.outfit(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.darkTextPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.darkTextPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.darkTextSecondary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.darkTextSecondary,
          height: 1.4,
        ),
        labelLarge: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.darkTextPrimary,
          letterSpacing: 0.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.darkTextMuted,
        ),
      );

  /// TextTheme completo para el tema claro (Light Theme)
  static TextTheme get lightTextTheme => TextTheme(
        displayLarge: GoogleFonts.outfit(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.lightTextPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.outfit(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.lightTextPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.lightTextPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.lightTextSecondary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.lightTextSecondary,
          height: 1.4,
        ),
        labelLarge: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.lightTextPrimary,
          letterSpacing: 0.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.lightTextMuted,
        ),
      );

  /// Retorna el TextTheme apropiado según el brillo del tema en contexto
  static TextTheme textThemeOf(BuildContext context) {
    return AppColors.isDark(context) ? darkTextTheme : lightTextTheme;
  }

  // ── 3. MÉTODOS ADAPTATIVOS REACTIVOS AL CONTEXTO ───────────────────────────
  static TextStyle displayLargeOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryOf(context),
        letterSpacing: -0.6,
        height: 1.05,
      );

  static TextStyle displayMediumOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryOf(context),
        letterSpacing: -0.4,
        height: 1.06,
      );

  static TextStyle titleLargeOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
      );

  static TextStyle bodyLargeOf(BuildContext context) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondaryOf(context),
        height: 1.5,
      );

  static TextStyle bodyMediumOf(BuildContext context) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondaryOf(context),
        height: 1.4,
      );

  static TextStyle buttonLabelOf(BuildContext context) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryOf(context),
        letterSpacing: 0.5,
      );

  static TextStyle captionOf(BuildContext context) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMutedOf(context),
      );
}
