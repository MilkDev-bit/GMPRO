/// @file lib/core/presentation/widgets/week_day_strip.dart
/// @description Tira de días MO–SU del layout tipo openGym: hoy resaltado con
/// círculo verde, días con actividad marcados con un punto, día seleccionable.
/// Mantiene los tokens de GymPro (verde = activo). Widget puro de presentación:
/// recibe el estado, no calcula fechas por su cuenta.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Estado de un día en la tira semanal.
class WeekDay {
  const WeekDay({
    required this.label,
    required this.dayNumber,
    this.isToday = false,
    this.isSelected = false,
    this.hasActivity = false,
    this.isRest = false,
  });

  /// Rótulo corto (MO, TU, …). Ya localizado por quien lo construye.
  final String label;
  final int dayNumber;
  final bool isToday;
  final bool isSelected;

  /// Hubo entrenamiento ese día (muestra punto).
  final bool hasActivity;

  /// Día de descanso planificado (atenúa).
  final bool isRest;
}

class WeekDayStrip extends StatelessWidget {
  const WeekDayStrip({
    super.key,
    required this.days,
    this.onDayTap,
  });

  final List<WeekDay> days;
  final ValueChanged<int>? onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < days.length; i++) ...[
          Expanded(child: _DayCell(day: days[i], onTap: onDayTap == null ? null : () => onDayTap!(i))),
          if (i != days.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, this.onTap});

  final WeekDay day;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    final selectedNumber = day.isToday || day.isSelected;

    final Color numberBg;
    final Color numberFg;
    if (day.isToday) {
      numberBg = emerald;
      numberFg = AppColors.surfaceOf(context);
    } else if (day.isSelected) {
      numberBg = emerald.withValues(alpha: 0.16);
      numberFg = emerald;
    } else {
      numberBg = Colors.transparent;
      numberFg = day.isRest
          ? AppColors.textMutedOf(context)
          : AppColors.textPrimaryOf(context);
    }

    final cell = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          day.label,
          style: AppTypography.captionOf(context).copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: numberBg,
            shape: BoxShape.circle,
            border: selectedNumber
                ? null
                : Border.all(color: AppColors.glassBorderOf(context), width: 1),
          ),
          child: Text(
            '${day.dayNumber}',
            style: AppTypography.numericMediumOf(context).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: numberFg,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Punto de actividad (o hueco para mantener la altura estable).
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: day.hasActivity ? emerald : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );

    if (onTap == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: cell,
    );
  }
}
