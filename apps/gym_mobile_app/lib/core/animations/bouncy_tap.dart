/// @file lib/core/animations/bouncy_tap.dart
/// @description Envoltura de animación IMPLÍCITA (rebote al tocar) reutilizable.
///
/// Reglas respetadas:
///   • R1: widget independiente; envuelve a un `child` cualquiera.
///   • R4: el estado local (`_pressed`) SOLO controla el valor visual (escala).
///     El `onTap` se delega tal cual al padre — aquí NO hay lógica de negocio,
///     ni mutaciones de BD, ni llamadas a API.

import 'package:flutter/material.dart';
import '../services/sound_manager.dart';

class BouncyTap extends StatefulWidget {
  const BouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.94,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOut,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;
  final Curve curve;

  /// Si true (default), el toque dispara SoundManager.playClick() — que ya
  /// incluye HapticFeedback.selectionClick(). Ponlo en false para toques mudos.
  final bool enableFeedback;

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap> {
  bool _pressed = false; // estado PURAMENTE visual (R4)

  void _set(bool v) {
    if (mounted) setState(() => _pressed = v);
  }

  void _handleTap() {
    // Feedback sensorial desacoplado (audio + háptica). No bloquea ni depende
    // del onTap de negocio, que se ejecuta a continuación intacto.
    if (widget.enableFeedback) SoundManager.playClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null ? null : _handleTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: widget.duration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}
