/// @file lib/core/services/widgets/live_activity_service.dart
/// @description Servicio para gestionar el cronómetro de descanso entre series en la
/// Isla Dinámica (Dynamic Island) y Pantalla de Bloqueo de iOS 16.1+ mediante ActivityKit.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'widget_payloads.dart';

abstract class LiveActivityService {
  /// Verifica si las Actividades en Vivo están soportadas por el sistema operativo y autorizadas por el usuario.
  Future<bool> get isLiveActivitySupported;

  /// Inicia o reactiva el cronómetro de descanso en la Isla Dinámica / Lockscreen.
  Future<void> startRestTimerActivity({
    required String exerciseName,
    required int currentSeries,
    required int totalSeries,
    required int restDurationSeconds,
  });

  /// Actualiza en tiempo real el cronómetro de descanso (ej. si el usuario añade 30s más).
  Future<void> updateRestTimerActivity({
    required int remainingSeconds,
  });

  /// Finaliza inmediatamente la actividad en vivo (ej. cuando la serie inicia o el entrenamiento concluye).
  Future<void> endRestTimerActivity();
}

class LiveActivityServiceImpl implements LiveActivityService {
  static const MethodChannel _channel = MethodChannel('com.gympro.live_activities/workout');
  String? _currentActivityId;

  @override
  Future<bool> get isLiveActivitySupported async {
    if (!Platform.isIOS) return false;
    try {
      final bool supported = await _channel.invokeMethod('isSupported') as bool? ?? false;
      return supported;
    } on PlatformException catch (_) {
      return false;
    }
  }

  @override
  Future<void> startRestTimerActivity({
    required String exerciseName,
    required int currentSeries,
    required int totalSeries,
    required int restDurationSeconds,
  }) async {
    if (!Platform.isIOS) return;

    try {
      final now = DateTime.now().toUtc();
      final endTime = now.add(Duration(seconds: restDurationSeconds));
      _currentActivityId = 'workout_rest_${now.millisecondsSinceEpoch}';

      final payload = RestTimerLiveActivityPayload(
        activityId: _currentActivityId!,
        exerciseName: exerciseName,
        currentSeries: currentSeries,
        totalSeries: totalSeries,
        restDurationSeconds: restDurationSeconds,
        endTimeIso: endTime.toIso8601String(),
        isResting: true,
      );

      if (kDebugMode) {
        debugPrint('[LiveActivityService] Iniciando Live Activity en Dynamic Island: ${payload.toMap()}');
      }

      await _channel.invokeMethod('startRestTimer', payload.toMap());
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[LiveActivityService] Error al iniciar Live Activity: ${e.message}');
      }
    }
  }

  @override
  Future<void> updateRestTimerActivity({
    required int remainingSeconds,
  }) async {
    if (!Platform.isIOS || _currentActivityId == null) return;

    try {
      final now = DateTime.now().toUtc();
      final newEndTime = now.add(Duration(seconds: remainingSeconds));

      final mapData = {
        'activity_id': _currentActivityId,
        'rest_duration_seconds': remainingSeconds,
        'end_time_iso': newEndTime.toIso8601String(),
        'is_resting': remainingSeconds > 0,
      };

      await _channel.invokeMethod('updateRestTimer', mapData);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[LiveActivityService] Error al actualizar Live Activity: ${e.message}');
      }
    }
  }

  @override
  Future<void> endRestTimerActivity() async {
    if (!Platform.isIOS || _currentActivityId == null) return;

    try {
      if (kDebugMode) {
        debugPrint('[LiveActivityService] Finalizando Live Activity $_currentActivityId');
      }

      await _channel.invokeMethod('endRestTimer', {'activity_id': _currentActivityId});
      _currentActivityId = null;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[LiveActivityService] Error al finalizar Live Activity: ${e.message}');
      }
    }
  }
}
