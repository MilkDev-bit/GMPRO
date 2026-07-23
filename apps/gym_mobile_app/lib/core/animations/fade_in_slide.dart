/// @file lib/core/animations/fade_in_slide.dart
/// @description Envoltorio PURO de entrada en cascada (fade + slide desde abajo).
///
/// Reglas respetadas:
///   • R4 Envoltorio puro: gestiona su propio AnimationController y lo libera en
///     dispose. En initState usa el `index` para un `Future.delayed` que escalona
///     el arranque → efecto cascada automático. Sin lógica de negocio.

import 'package:flutter/material.dart';

class FadeInSlide extends StatefulWidget {
  const FadeInSlide({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 450),
    this.stagger = const Duration(milliseconds: 70),
    this.offsetY = 24.0,
    this.curve = Curves.easeOutCubic,
    this.maxStaggerItems = 12,
  });

  /// Posición en la lista (0,1,2…): define el retardo escalonado.
  final int index;
  final Widget child;
  final Duration duration;

  /// Retardo entre elementos consecutivos.
  final Duration stagger;

  /// Desplazamiento inicial en píxeles (entra desde abajo).
  final double offsetY;
  final Curve curve;

  /// Tope de escalonado: a partir de aquí el retardo se satura para que listas
  /// largas no tarden segundos en aparecer.
  final int maxStaggerItems;

  @override
  State<FadeInSlide> createState() => _FadeInSlideState();
}

class _FadeInSlideState extends State<FadeInSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _fade = curved;
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100), // fracción del alto del hijo
      end: Offset.zero,
    ).animate(curved);

    // Cascada: retardo = index * stagger (saturado). El widget arranca solo.
    final steps = widget.index.clamp(0, widget.maxStaggerItems);
    final delay = widget.stagger * steps;
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // R4: liberación garantizada
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
