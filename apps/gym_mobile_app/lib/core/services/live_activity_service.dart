/// @file lib/core/services/live_activity_service.dart
/// @description Puente Dart → iOS (ActivityKit) para la Isla Dinámica.
///
/// ESTRATEGIA DE BATERÍA (clave del diseño):
///   1. La cuenta atrás del descanso NO se envía tick a tick. Se manda la FECHA
///      ABSOLUTA de fin (`restEndsAt`) y SwiftUI la renderiza con
///      `Text(timerInterval:)`, que decrementa por cuenta del sistema.
///      → Una sesión de 60 min genera ~20 mensajes, no ~3.600.
///   2. `update()` descarta payloads idénticos al último enviado (dedupe).
///   3. Se aplica un intervalo mínimo entre updates (`_minInterval`) para
///      respetar el presupuesto de actualizaciones de ActivityKit.
///
/// En Android / iOS < 16.1 todos los métodos son no-ops seguros.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Estado dinámico que se refleja en la Isla Dinámica.
@immutable
class WorkoutActivityState {
  const WorkoutActivityState({
    required this.currentExercise,
    this.nextExercise = '',
    this.setsDone = 0,
    this.setsTotal = 0,
    this.isResting = false,
    this.restEndsAt,
    this.accentHex = '#00F0FF',
  });

  final String currentExercise;
  final String nextExercise;
  final int setsDone;
  final int setsTotal;
  final bool isResting;

  /// Instante EXACTO en que acaba el descanso (no segundos restantes).
  final DateTime? restEndsAt;
  final String accentHex;

  Map<String, dynamic> toMap() => {
        'currentExercise': currentExercise,
        'nextExercise': nextExercise,
        'setsDone': setsDone,
        'setsTotal': setsTotal,
        'isResting': isResting,
        'restEndsAtEpochMs': restEndsAt?.millisecondsSinceEpoch ?? 0,
        'accentHex': accentHex,
      };

  /// Firma para deduplicar updates equivalentes.
  String get signature =>
      '$currentExercise|$nextExercise|$setsDone/$setsTotal|$isResting|'
      '${restEndsAt?.millisecondsSinceEpoch ?? 0}|$accentHex';
}

class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _channel = MethodChannel('gympro/live_activity');

  /// Intervalo mínimo entre actualizaciones enviadas al sistema.
  static const Duration _minInterval = Duration(seconds: 2);

  bool _active = false;
  String? _lastSignature;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isActive => _active;

  /// Solo iOS puede tener Live Activities.
  bool get _isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false; // Entornos de test / web
    }
  }

  /// ¿El dispositivo y el usuario permiten Live Activities?
  Future<bool> isSupported() async {
    if (!_isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] isSupported no disponible: ${e.code}');
      return false;
    } on MissingPluginException {
      return false; // Canal no registrado (iOS < 16.1 o build sin el bridge)
    }
  }

  /// Inicia la actividad al comenzar el entrenamiento.
  /// Devuelve el id de la actividad o null si no se pudo iniciar.
  Future<String?> start({
    required String routineName,
    required WorkoutActivityState state,
    DateTime? startedAt,
  }) async {
    if (!_isIOS) return null;
    try {
      final id = await _channel.invokeMethod<String>('start', {
        'routineName': routineName,
        'startedAtEpochMs':
            (startedAt ?? DateTime.now()).millisecondsSinceEpoch.toDouble(),
        'state': state.toMap(),
      });
      _active = id != null;
      _lastSignature = state.signature;
      _lastSentAt = DateTime.now();
      return id;
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] start falló: ${e.code} — ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Actualiza el estado. Ignora llamadas redundantes o demasiado seguidas.
  ///
  /// [force] omite el throttling (úsalo en cambios importantes: nuevo ejercicio,
  /// fin de descanso), nunca en un tick de cronómetro.
  Future<bool> update(WorkoutActivityState state, {bool force = false}) async {
    if (!_isIOS || !_active) return false;

    // 1. Dedupe: el estado no cambió realmente.
    if (state.signature == _lastSignature) return false;

    // 2. Throttle: respeta el presupuesto de ActivityKit.
    final elapsed = DateTime.now().difference(_lastSentAt);
    if (!force && elapsed < _minInterval) return false;

    try {
      final ok = await _channel.invokeMethod<bool>('update', {
        'state': state.toMap(),
      });
      if (ok ?? false) {
        _lastSignature = state.signature;
        _lastSentAt = DateTime.now();
      }
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] update falló: ${e.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Finaliza la actividad al terminar (o abandonar) el entrenamiento.
  Future<void> end({bool dismissImmediately = false}) async {
    if (!_isIOS || !_active) return;
    try {
      await _channel.invokeMethod<bool>('end', {
        'dismissImmediately': dismissImmediately,
      });
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] end falló: ${e.code}');
    } on MissingPluginException {
      // Canal ausente: nada que cerrar.
    } finally {
      _active = false;
      _lastSignature = null;
    }
  }
}
