/// @file lib/features/auth/presentation/widgets/neon_glow_background.dart
/// @description Fondo dinámico con resplandor radial neón púrpura/rosa estilo input_file_0.png.

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class NeonGlowBackground extends StatelessWidget {
  final Widget child;
  const NeonGlowBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Fondo base Obsidian
        Container(color: AppColors.background),

        // Resplandor superior izquierdo (Púrpura eléctrico)
        Positioned(
          top: -120,
          left: -80,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.neonPurple.withValues(alpha: 0.35),
                  AppColors.neonPurple.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Resplandor inferior derecho (Rosa vibrante)
        Positioned(
          bottom: -100,
          right: -60,
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.neonPink.withValues(alpha: 0.28),
                  AppColors.neonPink.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Contenido superior
        SafeArea(child: child),
      ],
    );
  }
}
