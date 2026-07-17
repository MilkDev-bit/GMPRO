/// @file lib/core/presentation/widgets/pressable.dart
/// @description Envoltorio táctil premium con FÍSICAS DE RESORTE (SpringSimulation)
/// y retroalimentación háptica acoplada. Al presionar, el hijo se comprime a 0.95;
/// al soltar, regresa con un rebote elegante (no una curva estática). Unifica los
/// pilares "Spring Physics" y "Háptica multimodal" para todos los botones de acción.
///
/// Rendimiento (120 FPS):
///   • Un solo AnimationController.unbounded por botón; `Transform.scale` en el
///     `builder` con el hijo pasado como `child` (no se reconstruye).
///   • La háptica se dispara en el gesto, nunca en el hilo de dibujado.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

enum PressHaptic { none, selection, light, medium }

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.95,
    this.haptic = PressHaptic.selection,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Escala mínima al mantener presionado (0.95 = compresión sutil premium).
  final double pressedScale;
  final PressHaptic haptic;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  // Controller "unbounded": su valor ES la escala (permite overshoot del resorte).
  late final AnimationController _controller =
      AnimationController.unbounded(vsync: this, value: 1.0);

  // Resorte crítico-suave: rebota lo justo para sentirse táctil, sin oscilar feo.
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 520, damping: 20);

  void _fireHaptic() {
    switch (widget.haptic) {
      case PressHaptic.none:
        break;
      case PressHaptic.selection:
        HapticFeedback.selectionClick();
        break;
      case PressHaptic.light:
        HapticFeedback.lightImpact();
        break;
      case PressHaptic.medium:
        HapticFeedback.mediumImpact();
        break;
    }
  }

  void _onDown(_) {
    if (!widget.enabled) return;
    _fireHaptic();
    _controller.animateTo(
      widget.pressedScale,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _springBack() {
    // Rebote físico desde la escala actual de vuelta a 1.0.
    _controller.animateWith(
      SpringSimulation(_spring, _controller.value, 1.0, 0.0),
    );
  }

  void _onUp(_) {
    if (!widget.enabled) return;
    _springBack();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _springBack,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
