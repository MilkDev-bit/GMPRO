/// @file lib/features/workout/presentation/widgets/media_preview_card.dart
/// @description Tarjeta grande de previsualización del ejercicio (GIF/vídeo). Botones
/// superpuestos redondeados en las esquinas inferiores: "Minimize" y "Tap to pause".
/// El widget es agnóstico del reproductor: recibe `media` (el Image/VideoPlayer ya
/// construido) y expone los callbacks. Tokens GymPro.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class MediaPreviewCard extends StatelessWidget {
  const MediaPreviewCard({
    super.key,
    this.media,
    required this.onMinimize,
    required this.onTogglePause,
    this.isPaused = false,
    this.aspectRatio = 16 / 10,
  });

  /// Contenido multimedia ya construido (Image.network del GIF, VideoPlayer, etc.).
  final Widget? media;
  final VoidCallback onMinimize;
  final VoidCallback onTogglePause;
  final bool isPaused;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: GestureDetector(
          onTap: onTogglePause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fondo / media.
              Container(
                color: AppColors.surfaceElevatedOf(context),
                child: media ??
                    Center(
                      child: Icon(Icons.play_circle_outline_rounded,
                          size: 48, color: AppColors.textMutedOf(context)),
                    ),
              ),
              // Velo de pausa.
              if (isPaused)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: Icon(Icons.play_arrow_rounded,
                      size: 56, color: Colors.white.withValues(alpha: 0.92)),
                ),
              // Botones inferiores.
              Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                child: _OverlayButton(
                  icon: Icons.close_fullscreen_rounded,
                  label: 'Minimize',
                  onTap: onMinimize,
                ),
              ),
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: _OverlayButton(
                  icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  label: isPaused ? 'Tap to play' : 'Tap to pause',
                  onTap: onTogglePause,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.captionOf(context).copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
