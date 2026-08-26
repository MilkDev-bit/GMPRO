/// @file lib/core/presentation/widgets/filter_chip_row.dart
/// @description Fila horizontal deslizable de chips de filtro (All / Back / Chest…).
/// El chip activo se tinta en verde; el resto queda neutro. Reutiliza la geometría de
/// PillTag pero con estado de selección. Tokens GymPro. Controlado por selectedIndex.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = AppSpacing.screenPadding,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final active = i == selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active
                    ? emerald.withValues(alpha: 0.16)
                    : AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: active
                      ? emerald.withValues(alpha: 0.45)
                      : AppColors.glassBorderOf(context),
                  width: 1,
                ),
              ),
              child: Text(
                labels[i],
                style: AppTypography.buttonLabelOf(context).copyWith(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? emerald : AppColors.textSecondaryOf(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
