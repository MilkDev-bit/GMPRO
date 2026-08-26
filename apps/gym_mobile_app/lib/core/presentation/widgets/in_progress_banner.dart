/// @file lib/core/presentation/widgets/in_progress_banner.dart
/// @description Banner "hoy" del layout tipo openGym: rótulo (TODAY · Push Day),
/// estado (In Progress / Ready) y CTA "Resume"/"Start". Tinte ámbar cuando hay una
/// sesión a medias (retomar) y verde cuando está listo para empezar. Mantiene los
/// tokens de GymPro. Usa Pressable para el feedback táctil ya definido en el sistema.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'pressable.dart';

class InProgressBanner extends StatelessWidget {
  const InProgressBanner({
    super.key,
    required this.title,
    required this.onResume,
    this.eyebrow = 'TODAY',
    this.subtitle,
    this.inProgress = false,
    this.ctaLabel,
    this.icon,
  });

  /// Nombre de la rutina de hoy (p. ej. "Push Day").
  final String title;

  /// Rótulo superior en versalitas.
  final String eyebrow;

  /// Texto secundario opcional (p. ej. "6 ejercicios · 45 min").
  final String? subtitle;

  /// true = hay una sesión a medias → tinte ámbar y CTA "Resume".
  final bool inProgress;

  /// Etiqueta del botón (por defecto: "Resume" o "Start").
  final String? ctaLabel;
  final IconData? icon;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final accent = inProgress
        ? AppColors.warningOf(context)
        : AppColors.accentEmeraldOf(context);
    final statusText = inProgress ? 'In Progress' : 'Ready';
    final cta = ctaLabel ?? (inProgress ? 'Resume' : 'Start');
    final ctaIcon = icon ?? (inProgress ? Icons.play_arrow_rounded : Icons.bolt_rounded);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          // Barra de acento vertical (ancla el color de estado sin saturar).
          Container(
            width: 3,
            height: 44,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      eyebrow,
                      style: AppTypography.captionOf(context).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: AppTypography.captionOf(context).copyWith(
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.captionOf(context).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.numericMediumOf(context).copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMediumOf(context).copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Pressable(
            haptic: PressHaptic.medium,
            onTap: onResume,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ctaIcon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    cta,
                    style: AppTypography.buttonLabelOf(context).copyWith(
                      fontSize: 14,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
