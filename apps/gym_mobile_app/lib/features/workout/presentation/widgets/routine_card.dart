/// @file lib/features/workout/presentation/widgets/routine_card.dart
/// @description Tarjeta de rutina creada (sección "Routines"): icono cuadrado verde,
/// título ("Push Day") y nº de ejercicios ("6 exercises"). Incluye RoutinesHeader con
/// el botón "+ New" en verde. Tokens GymPro.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class RoutineCard extends StatelessWidget {
  const RoutineCard({
    super.key,
    required this.title,
    required this.exerciseCount,
    this.icon = Icons.fitness_center_rounded,
    this.accent,
    this.onTap,
  });

  final String title;
  final int exerciseCount;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accentC = accent ?? AppColors.accentEmeraldOf(context);
    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap ?? () {},
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentC.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: accentC.withValues(alpha: 0.35), width: 1),
              ),
              child: Icon(icon, size: 22, color: accentC),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.buttonLabelOf(context).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$exerciseCount exercises',
                    style: AppTypography.bodyMediumOf(context).copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMutedOf(context)),
          ],
        ),
      ),
    );
  }
}

/// Cabecera de la sección "Routines" con botón "+ New" verde.
class RoutinesHeader extends StatelessWidget {
  const RoutinesHeader({super.key, required this.onNew, this.title = 'Routines'});

  final String title;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.displayMediumOf(context).copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
        Pressable(
          haptic: PressHaptic.light,
          onTap: onNew,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: emerald.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: emerald.withValues(alpha: 0.45), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 18, color: emerald),
                const SizedBox(width: 4),
                Text(
                  'New',
                  style: AppTypography.buttonLabelOf(context).copyWith(
                    fontSize: 14,
                    color: emerald,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
