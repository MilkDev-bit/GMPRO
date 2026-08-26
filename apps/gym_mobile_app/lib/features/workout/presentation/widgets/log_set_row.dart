/// @file lib/features/workout/presentation/widgets/log_set_row.dart
/// @description Fila de registro de una serie: identificador (nº de serie), steppers
/// -/+ para WEIGHT (KG) y REPS, y un checkbox circular a la derecha para marcarla
/// completada. Reutiliza QuantityStepper. Controlado por el provider de la sesión.
/// Tokens GymPro.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/presentation/widgets/quantity_stepper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class LogSetRow extends StatelessWidget {
  const LogSetRow({
    super.key,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.completed,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onToggleComplete,
    this.weightStep = 2.5,
  });

  final int setNumber;
  final double weightKg;
  final int reps;
  final bool completed;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final VoidCallback onToggleComplete;
  final double weightStep;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: completed
            ? emerald.withValues(alpha: 0.08)
            : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: completed
              ? emerald.withValues(alpha: 0.40)
              : AppColors.glassBorderOf(context),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Identificador de serie.
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedOf(context),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
            ),
            child: Text(
              '$setNumber',
              style: AppTypography.numericMediumOf(context).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: QuantityStepper(
              label: 'WEIGHT (KG)',
              value: weightKg,
              step: weightStep,
              decimals: 1,
              onChanged: onWeightChanged,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: QuantityStepper(
              label: 'REPS',
              value: reps.toDouble(),
              step: 1,
              min: 0,
              decimals: 0,
              onChanged: (v) => onRepsChanged(v.round()),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Checkbox circular.
          Pressable(
            haptic: PressHaptic.medium,
            onTap: onToggleComplete,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: completed ? emerald : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: completed ? emerald : AppColors.textMutedOf(context),
                  width: 2,
                ),
              ),
              child: completed
                  ? Icon(Icons.check_rounded,
                      size: 18, color: AppColors.surfaceOf(context))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
