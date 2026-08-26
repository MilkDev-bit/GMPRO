/// @file lib/features/workout/presentation/providers/guided_workout_provider.dart
/// @description Estado del ENTRENAMIENTO GUIADO (openGym): abre la sesión del día,
/// pre-carga los pesos con el motor de progresión, cuenta el descanso (Isla
/// Dinámica), detecta PR (1RM) y, al terminar, persiste la sesión para que la
/// próxima ya venga con los números correctos.
///
/// Batería/pantalla: mantiene la pantalla despierta SOLO mientras hay una sesión
/// activa (wakelock), y el rest timer usa la Live Activity nativa (cuenta atrás
/// del sistema), no un push por segundo.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/services/live_activity_service.dart';
import '../../domain/entities/workout_entities.dart';
import '../../domain/body/activity_heatmap.dart';
import '../../domain/training/one_rep_max.dart';
import '../../domain/training/session_builder.dart';
import '../../domain/training/set_log.dart';
import '../../data/activity_store.dart';
import '../../data/workout_history_store.dart';

/// Fase del runner.
enum GuidedPhase { idle, exercising, resting, finished }

/// Estado inmutable de la sesión guiada.
@immutable
class GuidedSessionState {
  const GuidedSessionState({
    this.phase = GuidedPhase.idle,
    this.plans = const [],
    this.exerciseIndex = 0,
    this.setIndex = 0,
    this.logged = const {},
    this.restEndsAt,
    this.prs = const {},
    this.currentWeightKg,
    this.currentReps,
    this.currentTimeSec,
    this.startedAt,
    this.routineName = '',
  });

  final GuidedPhase phase;
  final List<GuidedExercisePlan> plans;
  final int exerciseIndex;
  final int setIndex;

  /// exerciseIndex → series ya registradas.
  final Map<int, List<SetLog>> logged;

  /// Fin del descanso (absoluto) para UI + Live Activity.
  final DateTime? restEndsAt;

  /// ejercicioId con nuevo récord (1RM) en esta sesión.
  final Set<String> prs;

  /// Valores editables del stepper para la serie en curso.
  final double? currentWeightKg;
  final int? currentReps;
  final int? currentTimeSec;

  final DateTime? startedAt;
  final String routineName;

  GuidedExercisePlan? get currentPlan =>
      exerciseIndex < plans.length ? plans[exerciseIndex] : null;

  WorkoutExercise? get currentExercise => currentPlan?.exercise;
  WorkoutExercise? get nextExercise =>
      exerciseIndex + 1 < plans.length ? plans[exerciseIndex + 1].exercise : null;

  int get currentTargetSets => currentPlan?.targetSets ?? 0;
  int get setsDone => logged[exerciseIndex]?.length ?? 0;
  bool get isCurrentPr =>
      currentExercise != null && prs.contains(currentExercise!.ejercicioId);

  GuidedSessionState copyWith({
    GuidedPhase? phase,
    List<GuidedExercisePlan>? plans,
    int? exerciseIndex,
    int? setIndex,
    Map<int, List<SetLog>>? logged,
    DateTime? restEndsAt,
    bool clearRest = false,
    Set<String>? prs,
    double? currentWeightKg,
    int? currentReps,
    int? currentTimeSec,
    DateTime? startedAt,
    String? routineName,
  }) {
    return GuidedSessionState(
      phase: phase ?? this.phase,
      plans: plans ?? this.plans,
      exerciseIndex: exerciseIndex ?? this.exerciseIndex,
      setIndex: setIndex ?? this.setIndex,
      logged: logged ?? this.logged,
      restEndsAt: clearRest ? null : (restEndsAt ?? this.restEndsAt),
      prs: prs ?? this.prs,
      currentWeightKg: currentWeightKg ?? this.currentWeightKg,
      currentReps: currentReps ?? this.currentReps,
      currentTimeSec: currentTimeSec ?? this.currentTimeSec,
      startedAt: startedAt ?? this.startedAt,
      routineName: routineName ?? this.routineName,
    );
  }
}

class GuidedWorkoutNotifier extends StateNotifier<GuidedSessionState> {
  GuidedWorkoutNotifier(this._history, this._activity, this._liveActivity)
      : super(const GuidedSessionState());

  final WorkoutHistoryStore _history;
  final ActivityStore _activity;
  final LiveActivityService _liveActivity;

  Timer? _restTimer;

  static const String _accentHex = '#FF007A';

  // ── Arranque de la sesión del día ──────────────────────────────────────────
  Future<void> start(
    WorkoutDay day, {
    required String objetivo,
    String routineName = 'Entrenamiento',
  }) async {
    // Construir cada ejercicio con su objetivo pre-cargado desde el historial.
    final plans = <GuidedExercisePlan>[];
    for (final ex in day.ejercicios) {
      final hist = await _history.historyFor(ex.ejercicioId);
      plans.add(buildGuidedExercise(ex, objetivo: objetivo, history: hist));
    }
    if (plans.isEmpty) return;

    state = GuidedSessionState(
      phase: GuidedPhase.exercising,
      plans: plans,
      exerciseIndex: 0,
      setIndex: 0,
      logged: const {},
      startedAt: DateTime.now(),
      routineName: routineName,
    );
    _prefillCurrent();

    // Mantener la pantalla despierta durante la sesión.
    _safeWakelock(true);

    // Iniciar la Isla Dinámica.
    final first = plans.first;
    await _liveActivity.start(
      routineName: routineName,
      state: WorkoutActivityState(
        currentExercise: first.exercise.nombre,
        nextExercise: plans.length > 1 ? plans[1].exercise.nombre : '',
        setsDone: 0,
        setsTotal: first.targetSets,
        accentHex: _accentHex,
      ),
    );
  }

  /// Pre-rellena el stepper con el objetivo del ejercicio/serie actual.
  void _prefillCurrent() {
    final plan = state.currentPlan;
    if (plan == null) return;
    state = state.copyWith(
      currentWeightKg: plan.target.weightKg ?? 0,
      currentReps: plan.target.reps,
      currentTimeSec: plan.target.timeSec,
    );
  }

  // ── Ajustes del stepper ─────────────────────────────────────────────────────
  void adjustWeight(double deltaKg) {
    final w = ((state.currentWeightKg ?? 0) + deltaKg);
    state = state.copyWith(currentWeightKg: w < 0 ? 0 : w);
    HapticFeedback.selectionClick();
  }

  void adjustReps(int delta) {
    final r = ((state.currentReps ?? 0) + delta);
    state = state.copyWith(currentReps: r < 0 ? 0 : r);
    HapticFeedback.selectionClick();
  }

  void adjustTime(int deltaSec) {
    final t = ((state.currentTimeSec ?? 0) + deltaSec);
    state = state.copyWith(currentTimeSec: t < 0 ? 0 : t);
    HapticFeedback.selectionClick();
  }

  // ── Registrar la serie en curso ─────────────────────────────────────────────
  Future<void> logCurrentSet() async {
    final plan = state.currentPlan;
    if (plan == null || state.phase != GuidedPhase.exercising) return;

    final set = SetLog(
      weightKg: state.currentWeightKg ?? 0,
      reps: state.currentReps ?? 0,
      timeSec: state.currentTimeSec,
      completed: true,
    );

    final logged = Map<int, List<SetLog>>.from(state.logged);
    final list = List<SetLog>.from(logged[state.exerciseIndex] ?? const []);
    list.add(set);
    logged[state.exerciseIndex] = list;

    // Detección de PR (1RM) contra el histórico de este ejercicio.
    final prs = Set<String>.from(state.prs);
    await _checkPr(plan.exercise.ejercicioId, list, prs);

    state = state.copyWith(logged: logged, prs: prs);
    HapticFeedback.mediumImpact();

    // Descanso tras la serie (openGym: rest timer). El último set del último
    // ejercicio no descansa: se finaliza.
    final isLastSet = list.length >= plan.targetSets;
    final isLastExercise = state.exerciseIndex >= state.plans.length - 1;
    if (isLastSet && isLastExercise) {
      await finish();
      return;
    }
    _startRest(plan.exercise.descansoSeg);
  }

  Future<void> _checkPr(String ejercicioId, List<SetLog> sessionSets, Set<String> prs) async {
    final now = estimateOneRepMax(sessionSets);
    if (now == null) return;
    final hist = await _history.historyFor(ejercicioId);
    final prev = bestOneRepMaxOverSessions(hist);
    if (prev == null || now.estimateKg > prev.estimateKg + 0.01) {
      prs.add(ejercicioId);
    }
  }

  // ── Descanso ────────────────────────────────────────────────────────────────
  void _startRest(int seconds) {
    _restTimer?.cancel();
    final endsAt = DateTime.now().add(Duration(seconds: seconds));
    state = state.copyWith(phase: GuidedPhase.resting, restEndsAt: endsAt);

    // Actualiza la Isla Dinámica UNA vez con la fecha de fin (cuenta atrás nativa).
    _pushLiveActivity(isResting: true, restEndsAt: endsAt);

    _restTimer = Timer(Duration(seconds: seconds), () {
      HapticFeedback.heavyImpact();
      _advanceAfterRest();
    });
  }

  /// Saltar el descanso manualmente.
  void skipRest() {
    _restTimer?.cancel();
    _advanceAfterRest();
  }

  void _advanceAfterRest() {
    final done = state.logged[state.exerciseIndex]?.length ?? 0;
    final plan = state.currentPlan;
    if (plan == null) return;

    if (done < plan.targetSets) {
      // Siguiente serie del MISMO ejercicio.
      state = state.copyWith(
        phase: GuidedPhase.exercising,
        setIndex: done,
        clearRest: true,
      );
      _prefillCurrent();
      _pushLiveActivity(isResting: false);
    } else {
      // Siguiente EJERCICIO.
      final nextIdx = state.exerciseIndex + 1;
      if (nextIdx >= state.plans.length) {
        finish();
        return;
      }
      state = state.copyWith(
        phase: GuidedPhase.exercising,
        exerciseIndex: nextIdx,
        setIndex: 0,
        clearRest: true,
      );
      _prefillCurrent();
      _pushLiveActivity(isResting: false);
    }
  }

  // ── Finalizar / abandonar ───────────────────────────────────────────────────
  Future<void> finish() async {
    _restTimer?.cancel();

    // Persistir cada ejercicio como una ExerciseSession (alimenta la próxima).
    final now = DateTime.now();
    for (int i = 0; i < state.plans.length; i++) {
      final sets = state.logged[i];
      if (sets == null || sets.isEmpty) continue;
      await _history.appendSession(
        state.plans[i].exercise.ejercicioId,
        ExerciseSession(date: now, sets: sets),
      );
    }

    // Registrar la sesión para el heatmap (fecha + duración real).
    final started = state.startedAt ?? now;
    final minutes = now.difference(started).inMinutes.clamp(1, 600);
    await _activity.append(ActivityRecord(date: now, minutes: minutes));

    _safeWakelock(false);
    await _liveActivity.end();
    state = state.copyWith(phase: GuidedPhase.finished, clearRest: true);
  }

  /// Abandonar sin guardar (p. ej. el usuario sale a mitad).
  Future<void> abort() async {
    _restTimer?.cancel();
    _safeWakelock(false);
    await _liveActivity.end(dismissImmediately: true);
    state = const GuidedSessionState();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  void _pushLiveActivity({required bool isResting, DateTime? restEndsAt}) {
    final ex = state.currentExercise;
    if (ex == null) return;
    _liveActivity.update(
      WorkoutActivityState(
        currentExercise: ex.nombre,
        nextExercise: state.nextExercise?.nombre ?? '',
        setsDone: state.setsDone,
        setsTotal: state.currentTargetSets,
        isResting: isResting,
        restEndsAt: restEndsAt,
        accentHex: _accentHex,
      ),
      force: true,
    );
  }

  void _safeWakelock(bool enable) {
    try {
      enable ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {
      // Plataforma sin soporte: ignorar.
    }
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _safeWakelock(false);
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final workoutHistoryStoreProvider = Provider<WorkoutHistoryStore>((ref) {
  return SharedPrefsWorkoutHistoryStore();
});

final activityStoreProvider = Provider<ActivityStore>((ref) {
  return SharedPrefsActivityStore();
});

final guidedWorkoutProvider =
    StateNotifierProvider<GuidedWorkoutNotifier, GuidedSessionState>((ref) {
  return GuidedWorkoutNotifier(
    ref.watch(workoutHistoryStoreProvider),
    ref.watch(activityStoreProvider),
    LiveActivityService.instance,
  );
});
