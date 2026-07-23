/// @file lib/core/animations/rive_state_machine_view.dart
/// @description Widget AISLADO que renderiza un asset Rive con State Machine.
///
/// Reglas respetadas:
///   • R1 Encapsulamiento: es un widget independiente; NO contiene lógica de
///     negocio. Expone el `StateMachineController` vía `onControllerReady` para
///     que el PADRE dirija los inputs (SMIBool/SMINumber/SMITrigger).
///   • R2 Fallback: carga el .riv manualmente; ante CUALQUIER error (asset
///     ausente/corrupto/state machine inexistente) muestra `fallback` — nunca
///     una pantalla roja.
///   • R4 Estado: no muta BD ni llama APIs; solo pinta.

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

class RiveStateMachineView extends StatefulWidget {
  const RiveStateMachineView({
    super.key,
    required this.asset,
    required this.stateMachineName,
    required this.fallback,
    this.onControllerReady,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  /// Ruta del .riv (ej. 'assets/rive/avatar.riv').
  final String asset;

  /// Nombre EXACTO de la State Machine dentro del .riv.
  final String stateMachineName;

  /// Widget estático a mostrar si el asset no carga (R2). Suele ser el mismo
  /// Icon/Image que ya usabas antes de la animación.
  final Widget fallback;

  /// Se invoca UNA vez cuando la State Machine está lista. El padre guarda el
  /// controlador y busca sus inputs: `controller.findSMI('Look') as SMINumber`.
  final void Function(StateMachineController controller)? onControllerReady;

  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<RiveStateMachineView> createState() => _RiveStateMachineViewState();
}

class _RiveStateMachineViewState extends State<RiveStateMachineView> {
  Artboard? _artboard;
  StateMachineController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await RiveFile.asset(widget.asset);
      final artboard = file.mainArtboard;
      final controller =
          StateMachineController.fromArtboard(artboard, widget.stateMachineName);
      if (controller == null) {
        // La State Machine no existe con ese nombre → fallback.
        if (mounted) setState(() => _failed = true);
        return;
      }
      artboard.addController(controller);
      _controller = controller;
      widget.onControllerReady?.call(controller);
      if (mounted) setState(() => _artboard = artboard);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose(); // libera la State Machine (R4: ciclo de vida limpio)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_failed) {
      content = widget.fallback;
    } else if (_artboard != null) {
      content = Rive(artboard: _artboard!, fit: widget.fit);
    } else {
      // Cargando: mantiene el layout estable con el propio fallback (silencioso).
      content = widget.fallback;
    }
    return SizedBox(width: widget.width, height: widget.height, child: content);
  }
}
