/// @file lib/core/animations/lottie_view.dart
/// @description Widget AISLADO para animaciones Lottie (onboarding en bucle o
/// éxito one-shot), con AnimationController gestionado en el ciclo de vida y
/// fallback estático.
///
/// Reglas respetadas:
///   • R1: widget independiente; el controlador es interno y opcionalmente se
///     expone al padre vía `onLoaded`.
///   • R2: `errorBuilder` → si el .json no carga, muestra `fallback`.
///   • R4: el AnimationController SOLO controla el valor visual. `onCompleted`
///     es un mero callback; la lógica de negocio (navegar, refrescar) vive en
///     el padre, no aquí.

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LottieView extends StatefulWidget {
  const LottieView({
    super.key,
    required this.asset,
    required this.fallback,
    this.repeat = false,
    this.autoPlay = true,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.onCompleted,
  });

  /// Ruta del .json (ej. 'assets/lottie/success.json').
  final String asset;

  /// Widget estático si el asset no carga (R2).
  final Widget fallback;

  /// true = bucle (onboarding); false = una sola pasada (éxito de pago).
  final bool repeat;
  final bool autoPlay;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Callback al terminar una pasada NO-loop. El padre decide qué hacer
  /// (cerrar diálogo, navegar…). NO metas mutaciones de estado aquí dentro.
  final VoidCallback? onCompleted;

  @override
  State<LottieView> createState() => _LottieViewState();
}

class _LottieViewState extends State<LottieView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    if (!widget.repeat && widget.onCompleted != null) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onCompleted!.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // libera el ticker (R4)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      widget.asset,
      controller: _controller,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // La duración real se conoce al cargar la composición: la aplicamos y
      // arrancamos (bucle o una pasada) SIN tocar nada de negocio.
      onLoaded: (composition) {
        _controller.duration = composition.duration;
        if (!widget.autoPlay) return;
        if (widget.repeat) {
          _controller.repeat();
        } else {
          _controller.forward(from: 0);
        }
      },
      // R2: fallback estático si el JSON falta o está corrupto.
      errorBuilder: (context, error, stackTrace) => widget.fallback,
    );
  }
}
