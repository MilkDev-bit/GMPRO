/// @file lib/core/presentation/widgets/quantity_stepper.dart
/// @description Control -/valor/+ para ajustar cantidades (peso, reps). Rótulo en
/// versalitas arriba, valor con figuras tabulares en el centro. Mantiene tokens de
/// GymPro. Usa Pressable para el feedback táctil del sistema. Widget controlado:
/// recibe value y emite onChanged (no guarda estado propio).

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'pressable.dart';

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.max = double.infinity,
    this.decimals = 0,
    this.suffix,
    this.accent,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;

  /// Decimales a mostrar (peso suele 1, reps 0).
  final int decimals;
  final String? suffix;
  final Color? accent;

  void _bump(double delta) {
    final next = (value + delta).clamp(min, max).toDouble();
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accentC = accent ?? AppColors.accentEmeraldOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionOf(context).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: () => _bump(-step),
              accent: accentC,
            ),
            Expanded(
              child: Text(
                suffix == null
                    ? value.toStringAsFixed(decimals)
                    : '${value.toStringAsFixed(decimals)} $suffix',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: AppTypography.numericMediumOf(context).copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: () => _bump(step),
              accent: accentC,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.accent});

  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      haptic: PressHaptic.light,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedOf(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
        ),
        child: Icon(icon, size: 20, color: accent),
      ),
    );
  }
}
