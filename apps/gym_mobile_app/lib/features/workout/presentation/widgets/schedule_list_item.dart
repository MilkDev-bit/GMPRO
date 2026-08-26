/// @file lib/features/workout/presentation/widgets/schedule_list_item.dart
/// @description Fila de día en la pantalla Plan: nombre del día (Monday…), badge de la
/// rutina asignada (PillTag: "Push Day" verde / "Rest" gris) y flecha ">". Superficie
/// neutra redondeada. Tokens GymPro.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/pill_tag.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class ScheduleListItem extends StatelessWidget {
  const ScheduleListItem({
    super.key,
    required this.dayLabel,
    required this.routineLabel,
    this.isRest = false,
    this.isToday = false,
    this.onTap,
  });

  /// Día completo (Monday, Tuesday…).
  final String dayLabel;

  /// Rutina asignada ("Push Day") o etiqueta de descanso ("Rest").
  final String routineLabel;
  final bool isRest;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: isToday
                  ? AppColors.accentEmeraldOf(context).withValues(alpha: 0.35)
                  : AppColors.glassBorderOf(context),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dayLabel,
                  style: AppTypography.buttonLabelOf(context).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isRest
                        ? AppColors.textSecondaryOf(context)
                        : AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              PillTag(
                label: routineLabel,
                tone: isRest ? PillTone.neutral : PillTone.active,
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textMutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}
