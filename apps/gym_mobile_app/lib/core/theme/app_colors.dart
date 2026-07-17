/// @file lib/core/theme/app_colors.dart
/// @description Paleta de colores estética "Neon Sport Dark Mode" inspirada en input_file_0.png e input_file_1.png.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Fondos y Superficies (Dark Obsidian & Deep Purple) ─────────────────────
  static const Color background = Color(0xFF0A0914);       // Fondo principal profundo
  static const Color surface = Color(0xFF151226);          // Tarjetas y modales (curvas orgánicas)
  static const Color surfaceElevated = Color(0xFF1E1B38);  // Superficie superior (botón / input)
  static const Color surfaceGlass = Color(0x3328234D);     // Glassmorphism translúcido

  // ── Colores Neón Vibrantes (input_file_0.png) ──────────────────────────────
  static const Color neonPink = Color(0xFFFF007A);         // Rosa eléctrico principal
  static const Color neonPinkLight = Color(0xFFFF4D9E);    // Resplandor rosa suave
  static const Color neonPurple = Color(0xFF9D00FF);       // Púrpura neón intenso
  static const Color neonViolet = Color(0xFF6C00FF);       // Violeta oscuro neón
  static const Color neonCyan = Color(0xFF00F0FF);         // Acento azul cian para métricas

  // ── Gradientes Estilizados ─────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [neonPurple, neonPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C1833), Color(0xFF110E21)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const RadialGradient backgroundGlow = RadialGradient(
    center: Alignment(-0.6, -0.4),
    radius: 1.2,
    colors: [Color(0x339D00FF), Color(0x11FF007A), Colors.transparent],
  );

  // ── Textos y Jerarquía ─────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);      // Blanco nítido
  static const Color textSecondary = Color(0xFFB0A8D4);    // Púrpura pastel legible
  static const Color textMuted = Color(0xFF68608C);        // Gris violeta apagado

  // ── Estados y Alertas ──────────────────────────────────────────────────────
  static const Color error = Color(0xFFFF3366);            // Rojo neón para alertas
  static const Color success = Color(0xFF00E699);          // Verde esmeralda neón
  static const Color warning = Color(0xFFFFB800);          // Ámbar neón
}
