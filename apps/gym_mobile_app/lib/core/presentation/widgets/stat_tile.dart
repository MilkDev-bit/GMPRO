/// @file lib/core/presentation/widgets/stat_tile.dart
/// @description Tile de estadística (icono + rótulo + número grande) para la
/// cuadrícula 2×2 de Stats (Workouts / This month / Streak / Weight). Cifras con
/// figuras tabulares para que no "tiemblen" al cambiar. Tokens de GymPro.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Color de acento del icono/rótulo (por defecto, texto secundario neutro).
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? AppColors.textSecondaryOf(context);
    final tile = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMediumOf(context).copyWith(
                    color: AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: AppTypography.numericLargeOf(context).copyWith(
              fontSize: 34,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: tile,
      ),
    );
  }
}

/// Cuadrícula 2×2 de tiles con el gap estándar.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: AppSpacing.md),
          if (i + 1 < tiles.length)
            Expanded(child: tiles[i + 1])
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ));
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: AppSpacing.md));
    }
    return Column(children: rows);
  }
}
