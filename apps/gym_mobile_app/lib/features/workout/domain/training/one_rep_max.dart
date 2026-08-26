/// @file lib/features/workout/domain/training/one_rep_max.dart
/// @description Estimación de 1RM (máximo para una repetición) y calculadora.
///
/// Fórmula de Epley: 1RM = w · (1 + reps/30). Es la que mejor se comporta en el
/// rango 1–12 reps. openGym: "won't guess above 12 reps" → filtramos series con
/// más de 12 reps porque la estimación se dispara y deja de ser fiable.

import 'package:flutter/foundation.dart';
import 'set_log.dart';

/// Reps máximas para las que se considera fiable estimar el 1RM.
const int kOneRepMaxRepCeiling = 12;

/// 1RM por Epley a partir de una carga y sus reps.
double epley1RM(double weightKg, int reps) {
  if (reps <= 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}

/// Carga estimada para lograr [reps] repeticiones dado un [oneRepMax] (Epley inv.).
/// Útil para la "calculadora de series que aún no has hecho".
double weightForReps(double oneRepMax, int reps) {
  if (reps <= 1) return oneRepMax;
  return oneRepMax / (1 + reps / 30.0);
}

/// Resultado de la estimación: valor + la serie que lo produjo.
@immutable
class OneRepMaxEstimate {
  const OneRepMaxEstimate({
    required this.estimateKg,
    required this.source,
    this.formula = 'Epley',
  });

  final double estimateKg;

  /// Serie "ganadora" (openGym: "it names which one").
  final SetLog source;
  final String formula;
}

/// Estima el 1RM tomando la MEJOR serie elegible (con carga, completada, ≤ tope de
/// reps). Devuelve null si no hay ninguna serie elegible (p. ej. solo bodyweight).
OneRepMaxEstimate? estimateOneRepMax(
  List<SetLog> sets, {
  int maxReps = kOneRepMaxRepCeiling,
}) {
  OneRepMaxEstimate? best;
  for (final s in sets) {
    if (!s.completed) continue;
    if (s.weightKg <= 0) continue; // bodyweight: no aplica 1RM por carga
    if (s.reps < 1 || s.reps > maxReps) continue;
    final est = epley1RM(s.weightKg, s.reps);
    if (best == null || est > best.estimateKg) {
      best = OneRepMaxEstimate(estimateKg: est, source: s);
    }
  }
  return best;
}

/// Mejor 1RM histórico a lo largo de varias sesiones (curva de progreso).
OneRepMaxEstimate? bestOneRepMaxOverSessions(List<ExerciseSession> history) {
  OneRepMaxEstimate? best;
  for (final session in history) {
    final e = estimateOneRepMax(session.sets);
    if (e != null && (best == null || e.estimateKg > best.estimateKg)) {
      best = e;
    }
  }
  return best;
}
