/// @file lib/features/workout/data/workout_history_store.dart
/// @description Persistencia local del historial de sesiones por ejercicio.
/// Es la fuente que alimenta al motor de progresión (pre-carga de pesos) y la
/// detección de PR. Local-first (SharedPreferences), sin depender del backend;
/// `fitness-service` puede sincronizarlo más adelante sin tocar esta interfaz.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/training/set_log.dart';

/// Serialización de SetLog ↔ JSON.
Map<String, dynamic> _setToJson(SetLog s) => {
      'w': s.weightKg,
      'r': s.reps,
      if (s.timeSec != null) 't': s.timeSec,
      if (s.rir != null) 'rir': s.rir,
      if (s.rpe != null) 'rpe': s.rpe,
      'c': s.completed,
    };

SetLog _setFromJson(Map<String, dynamic> j) => SetLog(
      weightKg: (j['w'] as num?)?.toDouble() ?? 0,
      reps: (j['r'] as num?)?.toInt() ?? 0,
      timeSec: (j['t'] as num?)?.toInt(),
      rir: (j['rir'] as num?)?.toDouble(),
      rpe: (j['rpe'] as num?)?.toDouble(),
      completed: (j['c'] as bool?) ?? true,
    );

Map<String, dynamic> _sessionToJson(ExerciseSession s) => {
      'd': s.date.toIso8601String(),
      's': s.sets.map(_setToJson).toList(),
    };

ExerciseSession _sessionFromJson(Map<String, dynamic> j) => ExerciseSession(
      date: DateTime.tryParse(j['d'] as String? ?? '') ?? DateTime.now(),
      sets: ((j['s'] as List<dynamic>?) ?? [])
          .map((e) => _setFromJson(e as Map<String, dynamic>))
          .toList(),
    );

/// Contrato para inyección/tests.
abstract class WorkoutHistoryStore {
  Future<List<ExerciseSession>> historyFor(String ejercicioId);
  Future<void> appendSession(String ejercicioId, ExerciseSession session);
}

/// Implementación local con SharedPreferences.
class SharedPrefsWorkoutHistoryStore implements WorkoutHistoryStore {
  SharedPrefsWorkoutHistoryStore({this.maxSessionsPerExercise = 30});

  /// Se conservan las últimas N sesiones por ejercicio (suficiente para
  /// progresión/PR; evita crecer sin control en el dispositivo).
  final int maxSessionsPerExercise;

  static const _prefix = 'gympro:whist:';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _key(String ejercicioId) => '$_prefix$ejercicioId';

  @override
  Future<List<ExerciseSession>> historyFor(String ejercicioId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(ejercicioId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>);
      // Guardadas de más antigua a más reciente.
      return list
          .map((e) => _sessionFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> appendSession(String ejercicioId, ExerciseSession session) async {
    final prefs = await _prefs;
    final current = await historyFor(ejercicioId);
    final updated = [...current, session];
    // Recortar a las últimas N (conserva las más recientes).
    final trimmed = updated.length > maxSessionsPerExercise
        ? updated.sublist(updated.length - maxSessionsPerExercise)
        : updated;
    await prefs.setString(
      _key(ejercicioId),
      jsonEncode(trimmed.map(_sessionToJson).toList()),
    );
  }
}
