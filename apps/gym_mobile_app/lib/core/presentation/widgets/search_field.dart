/// @file lib/core/presentation/widgets/search_field.dart
/// @description Buscador con icono de lupa y limpiar. Superficie neutra redondeada,
/// tokens GymPro. Controlado por un TextEditingController externo (o interno) para no
/// forzar estado propio en árboles Riverpod.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasText = controller?.text.isNotEmpty ?? false;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.md),
          Icon(Icons.search_rounded,
              size: 20, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTypography.bodyMediumOf(context).copyWith(
                color: AppColors.textPrimaryOf(context),
              ),
              cursorColor: AppColors.accentEmeraldOf(context),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: AppTypography.bodyMediumOf(context).copyWith(
                  color: AppColors.textMutedOf(context),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondaryOf(context)),
              onPressed: () {
                controller?.clear();
                onClear?.call();
                onChanged?.call('');
              },
            )
          else
            const SizedBox(width: AppSpacing.md),
        ],
      ),
    );
  }
}
