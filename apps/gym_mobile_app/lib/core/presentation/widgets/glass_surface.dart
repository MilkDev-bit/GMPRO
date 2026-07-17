/// @file lib/core/presentation/widgets/glass_surface.dart
/// @description Cristal premium ("real glass") reutilizable para toda la estética
/// Neon Sport Dark. No es solo un BackdropFilter con opacidad: añade un borde
/// interior specular de 1px (highlight blanco arriba-izquierda → transparente
/// abajo-derecha) que simula la refracción de la luz sobre un panel de vidrio.
///
/// Rendimiento (120 FPS):
///   • Un único BackdropFilter + un único trazo de borde (CustomPainter).
///   • RepaintBoundary aísla el desenfoque para que no repinte el árbol detrás.
///   • Sin sombras internas caras; el highlight es un stroke con shader (1 draw).

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blurSigma = 18,
    this.padding,
    this.tint,
    this.tintAlpha,
    this.gradient,
    this.specularOpacity = 0.20,
    this.boxShadow,
    this.margin,
    this.border,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Relleno base del cristal. Si es null, usa el tinte adaptativo del tema.
  final Color? tint;
  final double? tintAlpha;

  /// Alternativa al [tint]: un gradiente de relleno (p. ej. tinte de marca).
  final Gradient? gradient;

  /// Intensidad del highlight specular (blanco) en la esquina superior izquierda.
  final double specularOpacity;
  final List<BoxShadow>? boxShadow;

  /// Borde de acento opcional (además del highlight specular interno).
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final Color fill = tint ?? AppColors.glassColorOf(context, alpha: tintAlpha);

    Widget surface = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // Desenfoque orgánico: sigma moderado para que el fondo se "lea" difuso
        // sin convertirse en una mancha plana.
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: CustomPaint(
          // El borde specular se pinta ENCIMA del contenido del cristal.
          foregroundPainter: _SpecularBorderPainter(
            radius: borderRadius,
            highlightOpacity: specularOpacity,
            isDark: AppColors.isDark(context),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: gradient == null ? fill : null,
              gradient: gradient,
              borderRadius: radius,
              border: border,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (boxShadow != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
        child: surface,
      );
    }
    if (margin != null) {
      surface = Padding(padding: margin!, child: surface);
    }
    // Aísla el BackdropFilter para no repintar lo que hay detrás en cada frame.
    return RepaintBoundary(child: surface);
  }
}

/// Pinta el borde specular de 1px: un trazo con shader lineal
/// blanco@highlightOpacity (TL) → blanco@0 (BR), más una tenue línea inferior
/// oscura que aporta profundidad (efecto bisel de vidrio).
class _SpecularBorderPainter extends CustomPainter {
  const _SpecularBorderPainter({
    required this.radius,
    required this.highlightOpacity,
    required this.isDark,
  });

  final double radius;
  final double highlightOpacity;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Inset de 0.5px para que el trazo de 1px caiga dentro del ClipRRect.
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius))
        .deflate(0.5);

    // 1. Highlight specular (arriba-izquierda → transparente abajo-derecha).
    final specular = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: highlightOpacity),
          Colors.white.withValues(alpha: highlightOpacity * 0.25),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.35, 0.7],
      ).createShader(rect);
    canvas.drawRRect(rrect, specular);

    // 2. Sutilísima línea de sombra inferior para dar volumen al bisel.
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: [
          Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
          Colors.black.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5],
      ).createShader(rect);
    canvas.drawRRect(rrect, shade);
  }

  @override
  bool shouldRepaint(_SpecularBorderPainter old) =>
      old.radius != radius ||
      old.highlightOpacity != highlightOpacity ||
      old.isDark != isDark;
}
