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
  static const List<NavDestination> all = [
    NavDestination(
      label: 'Inicio',
      icon: Icons.home_outlined,
      iconSelected: Icons.home_rounded,
      accentColor: AppColors.neonPink,
    ),
    NavDestination(
      label: 'Acceso',
      icon: Icons.qr_code_scanner_outlined,
      iconSelected: Icons.qr_code_scanner_rounded,
      accentColor: AppColors.neonCyan,
    ),
    NavDestination(
      label: 'Nutrición',
      icon: Icons.restaurant_outlined,
      iconSelected: Icons.restaurant_rounded,
      accentColor: Color(0xFF00E699), // Verde esmeralda neón
    ),
    NavDestination(
      label: 'Rutinas',
      icon: Icons.fitness_center_outlined,
      iconSelected: Icons.fitness_center_rounded,
      accentColor: Color(0xFFFF9500), // Naranja neón vibrante
    ),
    NavDestination(
      label: 'Cuenta',
      icon: Icons.person_outlined,
      iconSelected: Icons.person_rounded,
      accentColor: AppColors.neonPurple,
    ),
  ];
}
