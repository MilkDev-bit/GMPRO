/// @file lib/features/workout/presentation/widgets/weight_tracker_card.dart
/// @description Tarjeta de peso corporal del Home: valor actual grande (87 kg),
/// tendencia hacia la meta, chips +Log / Goal y la gráfica minimalista con relleno
/// verde graduado (BodyWeightChart). Compone SectionCard + CardAction. Tokens GymPro.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/section_card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/body/body_weight.dart';
import 'body_weight_chart.dart';

class WeightTrackerCard extends StatelessWidget {
  const WeightTrackerCard({
    super.key,
    required this.series,
    required this.onLog,
    required this.onGoal,
    this.unit = 'kg',
  });

  final WeightSeries series;
  final VoidCallback onLog;
  final VoidCallback onGoal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final latest = series.latest;
    final remaining = series.remainingToGoalKg;

    return SectionCard(
      title: 'BODY WEIGHT',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CardAction(label: 'Log', icon: Icons.add_rounded, onTap: onLog),
          const SizedBox(width: AppSpacing.sm),
          CardAction(
            label: 'Goal',
            icon: Icons.flag_outlined,
            onTap: onGoal,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                latest == null ? '—' : latest.kg.toStringAsFixed(1),
                style: AppTypography.numericLargeOf(context).copyWith(
                  fontSize: 40,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  unit,
                  style: AppTypography.bodyMediumOf(context).copyWith(
                    color: AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (remaining != null && remaining.abs() >= 0.05)
                _RemainingBadge(remaining: remaining, unit: unit),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          BodyWeightChart(series: series, height: 160),
        ],
      ),
    );
  }
}

class _RemainingBadge extends StatelessWidget {
  const _RemainingBadge({required this.remaining, required this.unit});

  final double remaining;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    final text = '${remaining.abs().toStringAsFixed(1)} $unit to goal';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: emerald.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        text,
        style: AppTypography.captionOf(context).copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: emerald,
        ),
      ),
    );
  }
}
