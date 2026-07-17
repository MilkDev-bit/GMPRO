/// @file lib/core/theme/app_theme.dart
/// @description Configuración completa de ThemeData con instancias estáticas
/// darkTheme y lightTheme que responden automáticamente al System Theme del dispositivo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  // ── 1. DARK THEME (Neon Sport Obsidian) ────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      primaryColor: AppColors.neonPink,
      cardColor: AppColors.darkSurface,
      dividerColor: AppColors.darkGlassBorder,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.neonPink,
        onPrimary: Colors.white,
        secondary: AppColors.neonPurple,
        onSecondary: Colors.white,
        tertiary: AppColors.neonCyan,
        onTertiary: AppColors.darkBackground,   // texto oscuro sobre cian brillante
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        onSurfaceVariant: AppColors.darkTextSecondary,
        surfaceContainerHighest: AppColors.darkSurfaceElevated,
        outline: AppColors.darkTextMuted,
        outlineVariant: AppColors.darkGlassBorder,
        error: AppColors.error,
        onError: Colors.white,
      ),

      // Tipografía unificada e integrada
      textTheme: AppTypography.darkTextTheme,
      iconTheme: const IconThemeData(color: AppColors.darkTextPrimary, size: 24),

      // AppBar adaptativo con barra de estado clara para fondos oscuros
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
        titleTextStyle: AppTypography.titleLarge.copyWith(color: AppColors.darkTextPrimary),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.darkBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),

      // Curvas orgánicas amplias para tarjetas
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.darkGlassBorder, width: 1),
        ),
      ),

      // Campos de texto estilizados con foco neón
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.darkGlassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.darkGlassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.neonPink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.darkTextMuted),
      ),

      // Botones elevados en forma de píldora (Capsule Button)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.neonPink,
          elevation: 8,
          shadowColor: AppColors.neonPink.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: AppTypography.buttonLabel,
        ),
      ),
    );
  }

  // ── 2. LIGHT THEME (Sport High Contrast Glass) ─────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      primaryColor: AppColors.lightNeonPink,
      cardColor: AppColors.lightSurface,
      dividerColor: AppColors.lightGlassBorder,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightNeonPink,
        onPrimary: Colors.white,
        secondary: AppColors.lightNeonPurple,
        onSecondary: Colors.white,
        tertiary: AppColors.lightNeonCyan,
        onTertiary: Colors.white,               // #00768A es suficientemente oscuro
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        onSurfaceVariant: AppColors.lightTextSecondary,
        surfaceContainerHighest: AppColors.lightSurfaceElevated,
        outline: AppColors.lightTextMuted,
        outlineVariant: AppColors.lightGlassBorder,
        error: AppColors.lightError,            // antes #FF3366 (3.29:1 → fallaba)
        onError: Colors.white,
      ),

      // Tipografía unificada con contraste alto
      textTheme: AppTypography.lightTextTheme,
      iconTheme: const IconThemeData(color: AppColors.lightTextPrimary, size: 24),

      // AppBar adaptativo con barra de estado oscura para fondos claros
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
        titleTextStyle: AppTypography.titleLarge.copyWith(color: AppColors.lightTextPrimary),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.lightBackground,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),

      // Tarjetas con fondo blanco puro y borde sutil
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.lightGlassBorder, width: 1),
        ),
      ),

      // Campos de texto adaptados al tema claro
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lightGlassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lightGlassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lightNeonPink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.lightTextMuted),
      ),

      // Botones en cápsula adaptados con sombra de mayor contraste
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.lightNeonPink,
          elevation: 6,
          shadowColor: AppColors.lightNeonPink.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: AppTypography.buttonLabel,
        ),
      ),
    );
  }
}
