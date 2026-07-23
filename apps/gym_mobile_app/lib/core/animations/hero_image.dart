/// @file lib/core/animations/hero_image.dart
/// @description Imagen con transición Hero a pantalla completa. El `tag` es
/// OBLIGATORIO y debe ser único por dato (R3) para evitar
/// "Multiple Hero widgets share the same tag".
///
/// Reglas respetadas:
///   • R1: widget independiente, sin lógica de negocio.
///   • R2: `errorBuilder` de Image.network → placeholder si la URL falla.
///   • R3: `heroTag` requerido; el llamador debe pasar algo único
///     (ej. 'exercise-${item.id}').

import 'package:flutter/material.dart';

class HeroImage extends StatelessWidget {
  const HeroImage({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 16,
    this.enableFullScreen = true,
  });

  final String imageUrl;

  /// ÚNICO por elemento. Usa el id del modelo, nunca un literal fijo (R3).
  final Object heroTag;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final bool enableFullScreen;

  Widget _fallback(BuildContext context) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.white38),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      // R2: si la imagen no carga, placeholder — sin excepción.
      errorBuilder: (context, error, stackTrace) => _fallback(context),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _fallback(context),
    );

    final hero = Hero(
      tag: heroTag, // R3: único por dato
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: image,
      ),
    );

    if (!enableFullScreen) return hero;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (_, __, ___) => _HeroFullScreen(
            imageUrl: imageUrl,
            heroTag: heroTag,
            fallbackBuilder: _fallback,
          ),
        ),
      ),
      child: hero,
    );
  }
}

class _HeroFullScreen extends StatelessWidget {
  const _HeroFullScreen({
    required this.imageUrl,
    required this.heroTag,
    required this.fallbackBuilder,
  });

  final String imageUrl;
  final Object heroTag;
  final Widget Function(BuildContext) fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Hero(
            tag: heroTag, // MISMO tag → transición compartida
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => fallbackBuilder(c),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
