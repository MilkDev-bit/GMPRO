/// @file lib/core/presentation/widgets/segmented_control.dart
/// @description Selector segmentado horizontal (1M / 3M / 1Y / All). La opción activa
/// se resalta con una "pastilla" de superficie elevada que se desliza. Tokens GymPro.
/// Controlado: recibe selectedIndex, emite onChanged.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = segments.length;
          final segWidth = (constraints.maxWidth - 8) / n;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevatedOf(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                        color: AppColors.glassBorderOf(context), width: 1),
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < n; i++)
                    SizedBox(
                      width: segWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            segments[i],
                            textAlign: TextAlign.center,
                            style: AppTypography.buttonLabelOf(context).copyWith(
                              fontSize: 13,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == selectedIndex
                                  ? AppColors.textPrimaryOf(context)
                                  : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
