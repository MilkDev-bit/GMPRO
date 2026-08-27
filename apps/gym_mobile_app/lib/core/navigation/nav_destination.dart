/// @file lib/core/navigation/nav_destination.dart
/// @description Modelo de datos para cada destino de navegación del AppShell.
/// Define icono, etiqueta y color de acento neón de cada sección.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.iconSelected,
    required this.accentColor,
  });

  final String label;
  final IconData icon;
  final IconData iconSelected;
  final Color accentColor;

  /// Los 5 destinos principales de GymPro AI.
  /// Un ÚNICO acento (verde de sistema) para la pestaña activa, estilo iOS —
  /// se acabó el color neón distinto por pestaña.
  static const Color _navAccent = AppColors.neonEmerald;

  static const List<NavDestination> all = [
    NavDestination(
      label: 'Inicio',
      icon: Icons.home_outlined,
      iconSelected: Icons.home_rounded,
      accentColor: _navAccent,
    ),
    NavDestination(
      label: 'Acceso',
      icon: Icons.qr_code_scanner_outlined,
      iconSelected: Icons.qr_code_scanner_rounded,
      accentColor: _navAccent,
    ),
    NavDestination(
      label: 'Nutrición',
      icon: Icons.restaurant_outlined,
      iconSelected: Icons.restaurant_rounded,
      accentColor: _navAccent,
    ),
    NavDestination(
      label: 'Rutinas',
      icon: Icons.fitness_center_outlined,
      iconSelected: Icons.fitness_center_rounded,
      accentColor: _navAccent,
    ),
    NavDestination(
      label: 'Cuenta',
      icon: Icons.person_outlined,
      iconSelected: Icons.person_rounded,
      accentColor: _navAccent,
    ),
  ];
}
