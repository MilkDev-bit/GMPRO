/// @file lib/core/presentation/widgets/section_card.dart
/// @description Tarjeta de sección calmada (estilo openGym): superficie neutra
/// redondeada, sin glow, con cabecera opcional (título en versalitas + acción a la
/// derecha). Es el contenedor base de Home/Plan/Stats. Mantiene los tokens de GymPro.
///
/// Para superficies con desenfoque de fondo usar GlassSurface; esta tarjeta es la
/// versión SÓLIDA y tranquila que domina el layout de referencia.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.margin,
  });

  final Widget child;

  /// Rótulo de sección en versalitas (p. ej. "BODY WEIGHT"). Opcional.
  final String? title;

  /// Acción a la derecha de la cabecera (p. ej. "+ Log", "Goal").
  final Widget? trailing;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: AppTypography.captionOf(context).copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondaryOf(context),
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// Fila de acción de cabecera: icono + texto con color de acento (p. ej. "＋ Log").
class CardAction extends StatelessWidget {
  const CardAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accentEmeraldOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.buttonLabel.copyWith(fontSize: 14, color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
