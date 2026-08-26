/// @file lib/features/workout/presentation/widgets/exercise_meta_header.dart
/// @description Cabecera de un ejercicio en la sesión activa: título ("Cable Triceps
/// Pushdown") + icono de info, botones redondeados verdes para superset con el
/// ejercicio anterior/siguiente, y pills secundarias ("Triceps", "Cable"). Tokens
/// GymPro. Los pills reutilizan PillTag (info).

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/pill_tag.dart';
import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class ExerciseMetaHeader extends StatelessWidget {
  const ExerciseMetaHeader({
    super.key,
    required this.title,
    required this.tags,
    this.onInfo,
    this.onSupersetPrevious,
    this.onSupersetNext,
  });

  final String title;

  /// Etiquetas secundarias (grupo muscular, equipo…).
  final List<String> tags;
  final VoidCallback? onInfo;
  final VoidCallback? onSupersetPrevious;
  final VoidCallback? onSupersetNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.displayMediumOf(context).copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            if (onInfo != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.info_outline_rounded,
                    size: 20, color: AppColors.textSecondaryOf(context)),
                onPressed: onInfo,
              ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final t in tags) PillTag(label: t, tone: PillTone.info),
            ],
          ),
        ],
        if (onSupersetPrevious != null || onSupersetNext != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (onSupersetPrevious != null)
                Expanded(
                  child: _SupersetButton(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Superset previous',
                    onTap: onSupersetPrevious!,
                  ),
                ),
              if (onSupersetPrevious != null && onSupersetNext != null)
                const SizedBox(width: AppSpacing.sm),
              if (onSupersetNext != null)
                Expanded(
                  child: _SupersetButton(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Superset next',
                    onTap: onSupersetNext!,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SupersetButton extends StatelessWidget {
  const _SupersetButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Pressable(
      haptic: PressHaptic.light,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: emerald.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: emerald.withValues(alpha: 0.40), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: emerald),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.buttonLabelOf(context).copyWith(
                  fontSize: 13,
                  color: emerald,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
