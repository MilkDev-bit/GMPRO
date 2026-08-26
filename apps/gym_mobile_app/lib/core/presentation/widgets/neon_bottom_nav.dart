/// @file lib/core/presentation/widgets/neon_bottom_nav.dart
/// @description Barra de navegación inferior del layout tipo openGym: fondo con
/// desenfoque (glass), 4 destinos y un FAB central de "play" (empezar entrenamiento).
/// Mantiene los tokens de GymPro: destino activo en verde, resto neutro. Aislado con
/// RepaintBoundary para no repintar el contenido de la pantalla al animar.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'pressable.dart';

/// Ítem de la barra inferior calmada. Distinto de `core/navigation/NavDestination`
/// (ese lleva color de acento por pestaña); aquí el acento es único (verde) para
/// mantener la estética tranquila del rediseño.
class NavItem {
  const NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class NeonBottomNav extends StatelessWidget {
  const NeonBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onCenterTap,
    this.centerIcon = Icons.play_arrow_rounded,
  });

  /// Exactamente 4 destinos (2 a cada lado del FAB central).
  final List<NavItem> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCenterTap;
  final IconData centerIcon;

  @override
  Widget build(BuildContext context) {
    assert(destinations.length == 4, 'NeonBottomNav espera 4 destinos');
    final emerald = AppColors.accentEmeraldOf(context);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.sm + MediaQuery.of(context).padding.bottom,
              left: AppSpacing.sm,
              right: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context).withValues(alpha: 0.72),
              border: Border(
                top: BorderSide(color: AppColors.glassBorderOf(context), width: 1),
              ),
            ),
            child: Row(
              children: [
                _navItem(context, 0, emerald),
                _navItem(context, 1, emerald),
                _centerButton(context, emerald),
                _navItem(context, 2, emerald),
                _navItem(context, 3, emerald),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int index, Color emerald) {
    final d = destinations[index];
    final selected = index == currentIndex;
    final color =
        selected ? emerald : AppColors.textSecondaryOf(context);
    return Expanded(
      child: Pressable(
        haptic: PressHaptic.selection,
        onTap: () => onDestinationSelected(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionOf(context).copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centerButton(BuildContext context, Color emerald) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Pressable(
        haptic: PressHaptic.medium,
        onTap: onCenterTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [emerald, emerald.withValues(alpha: 0.82)],
            ),
            boxShadow: [
              BoxShadow(
                color: emerald.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(centerIcon, size: 30, color: AppColors.surfaceOf(context)),
        ),
      ),
    );
  }
}
