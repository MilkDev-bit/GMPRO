/// @file lib/features/auth/presentation/widgets/neon_glow_background.dart
/// @description Fondo dinámico con resplandor radial neón púrpura/rosa estilo premium.

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class NeonGlowBackground extends StatelessWidget {
  final Widget child;
  const NeonGlowBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Fondo base Obsidian profundo
        Container(color: const Color(0xFF080614)), // DarkTheme base

        // Orbe Cyan superior izquierdo (agrandado)
        Positioned(
          top: -150,
          left: -100,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.neonCyan.withValues(alpha: 0.4),
                  AppColors.neonCyan.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),

        // Orbe Magenta inferior derecho (agrandado)
        Positioned(
          bottom: -150,
          right: -100,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.neonPink.withValues(alpha: 0.35),
                  AppColors.neonPink.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),

        // Orbe Esmeralda central (sutil)
        Positioned(
          top: MediaQuery.of(context).size.height * 0.35,
          left: MediaQuery.of(context).size.width * 0.2,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.neonEmerald.withValues(alpha: 0.15),
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
