/// @file lib/features/workout/presentation/widgets/exercise_list_tile.dart
/// @description Fila de la biblioteca de ejercicios: miniatura a la izquierda, título,
/// subtítulo (músculos · equipo) y botón "+ Plan" verde a la derecha. El thumbnail es
/// agnóstico (se pasa el Widget ya construido: Image.network, etc.). Tokens GymPro.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class ExerciseListTile extends StatelessWidget {
  const ExerciseListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onAddToPlan,
    this.thumbnail,
    this.inPlan = false,
    this.onTap,
  });

  final String title;

  /// Ej.: "Triceps · Cable".
  final String subtitle;
  final VoidCallback onAddToPlan;

  /// Miniatura ya construida; si es null, muestra un placeholder neutro.
  final Widget? thumbnail;

  /// true = ya está en el plan → el botón muestra estado añadido.
  final bool inPlan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: thumbnail ??
                      Container(
                        color: AppColors.surfaceElevatedOf(context),
                        child: Icon(Icons.fitness_center_rounded,
                            size: 22, color: AppColors.textMutedOf(context)),
                      ),
                ),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMediumOf(context).copyWith(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Pressable(
                haptic: PressHaptic.light,
                onTap: onAddToPlan,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: inPlan
                        ? AppColors.surfaceElevatedOf(context)
                        : emerald.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: inPlan
                          ? AppColors.glassBorderOf(context)
                          : emerald.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        inPlan ? Icons.check_rounded : Icons.add_rounded,
                        size: 16,
                        color: inPlan ? AppColors.textSecondaryOf(context) : emerald,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        inPlan ? 'Added' : 'Plan',
                        style: AppTypography.buttonLabelOf(context).copyWith(
                          fontSize: 13,
                          color:
                              inPlan ? AppColors.textSecondaryOf(context) : emerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
