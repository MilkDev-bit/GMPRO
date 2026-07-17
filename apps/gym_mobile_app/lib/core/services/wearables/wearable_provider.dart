import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/workout/presentation/providers/workout_provider.dart';
import 'wearable_payloads.dart';
import 'wearable_service.dart';

/// Proveedor base del servicio singleton WearableService
final wearableServiceProvider = Provider<WearableService>((ref) {
  return WearableServiceImpl.instance;
});

/// Estado reactivo del controlador de relojes inteligentes
class WearableState {
  final bool isSupported;
  final bool isPaired;
  final bool isReachable;
  final SeriesCompletedWearAction? lastSeriesCompletedAction;

  const WearableState({
    this.isSupported = false,
    this.isPaired = false,
    this.isReachable = false,
    this.lastSeriesCompletedAction,
  });

  WearableState copyWith({
    bool? isSupported,
    bool? isPaired,
    bool? isReachable,
    SeriesCompletedWearAction? lastSeriesCompletedAction,
  }) {
    return WearableState(
      isSupported: isSupported ?? this.isSupported,
      isPaired: isPaired ?? this.isPaired,
      isReachable: isReachable ?? this.isReachable,
      lastSeriesCompletedAction: lastSeriesCompletedAction ?? this.lastSeriesCompletedAction,
    );
  }
}

/// Controlador principal de eventos entre teléfono y relojes
class WearableNotifier extends StateNotifier<WearableState> {
  final WearableService _service;
  final Ref _ref;

  WearableNotifier(this._service, this._ref) : super(const WearableState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _service.initialize();
    await checkConnectionStatus();

    // Registrar oyente para cuando el usuario presiona "Serie Completada" desde el reloj
    _service.setOnSeriesCompletedCallback((action) {
      debugPrint('⌚ [WearableNotifier] ¡Serie terminada en el reloj! Ejercicio: ${action.exerciseId} | Serie: ${action.completedSeries}');
      HapticFeedback.heavyImpact(); // Vibración fuerte en el teléfono para confirmar
      state = state.copyWith(lastSeriesCompletedAction: action);
      try {
        final currentPlan = _ref.read(workoutProvider).plan;
        if (currentPlan != null) {
          debugPrint('💪 [Wearable Integration] Rutina "${currentPlan.nombre}" sincronizada con serie ${action.completedSeries}.');
        }
      } catch (e) {
        debugPrint('ℹ️ [Wearable Integration] workoutProvider no activo en este momento: $e');
      }
    });
  }

  /// Verifica si hay un Apple Watch o Android Wear OS pareado y accesible.
  Future<void> checkConnectionStatus() async {
    final supported = await _service.isSupported;
    final paired = await _service.isPaired;
    final reachable = await _service.isReachable;

    state = state.copyWith(
      isSupported: supported,
      isPaired: paired,
      isReachable: reachable,
    );
  }

  /// Sincroniza la rutina y ejercicio activo del PageView en la muñeca del usuario.
  Future<void> syncWorkout({
    required String exerciseId,
    required String exerciseName,
    required int currentSeries,
    required int totalSeries,
    required String reps,
    int restSeconds = 90,
    double? weightKg,
    bool isWorkoutActive = true,
  }) async {
    final payload = WorkoutWearPayload(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      currentSeries: currentSeries,
      totalSeries: totalSeries,
      reps: reps,
      restDurationSeconds: restSeconds,
      weightKg: weightKg,
      isWorkoutActive: isWorkoutActive,
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    await _service.syncActiveWorkout(payload);
  }

  /// Sincroniza el código QR dinámico de 30 segundos con el widget del reloj.
  Future<void> syncQrToken({
    required String token,
    required DateTime expiresAt,
    String userFullName = 'Atleta GymPro',
    String membershipTier = 'PRO',
  }) async {
    final payload = QrAccessWearPayload(
      qrToken: token,
      expiresAtIso: expiresAt.toUtc().toIso8601String(),
      refreshIntervalSeconds: 30,
      userFullName: userFullName,
      membershipTier: membershipTier,
    );

    await _service.syncDynamicQrToken(payload);
  }
}

final wearableControllerProvider =
    StateNotifierProvider<WearableNotifier, WearableState>((ref) {
  final service = ref.watch(wearableServiceProvider);
  return WearableNotifier(service, ref);
});
