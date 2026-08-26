/// @file lib/core/presentation/widgets/pill_tag.dart
/// @description Etiqueta redonda (pill) del layout tipo openGym: "Push Day" (activo),
/// "Rest" (neutro), "In Progress"/"Resume" (en curso). Mantiene la paleta de GymPro:
/// verde = positivo/activo, ámbar = en curso, gris = neutro.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Intención semántica del pill (define el color desde los tokens de marca).
enum PillTone { active, inProgress, neutral, info }

class PillTag extends StatelessWidget {
  const PillTag({
    super.key,
    required this.label,
    this.icon,
    this.tone = PillTone.neutral,
    this.filled = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final PillTone tone;

  /// true = fondo tintado (CTA "Resume"); false = solo texto con leve fondo.
  final bool filled;
  final VoidCallback? onTap;

  Color _accent(BuildContext c) {
    switch (tone) {
      case PillTone.active:
        return AppColors.accentEmeraldOf(c);
      case PillTone.inProgress:
        return AppColors.warningOf(c);
      case PillTone.info:
        return AppColors.accentCyanOf(c);
      case PillTone.neutral:
        return AppColors.textSecondaryOf(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final bg = tone == PillTone.neutral
        ? AppColors.surfaceElevatedOf(context)
        : accent.withValues(alpha: filled ? 0.20 : 0.12);
    final border = tone == PillTone.neutral
        ? AppColors.glassBorderOf(context)
        : accent.withValues(alpha: 0.40);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
