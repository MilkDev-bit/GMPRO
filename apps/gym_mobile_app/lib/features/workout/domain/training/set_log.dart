/// @file lib/features/workout/domain/training/set_log.dart
/// @description Modelos PUROS del motor de entrenamiento (progresión + 1RM).
///
/// Portados conceptualmente de openGym (AGPL): se reimplementan los ALGORITMOS
/// (Epley, Greyskull LP, doble progresión…), que son conocimiento público, no su
/// código. Todo aquí es determinista y sin dependencias de Flutter → testeable
/// con `flutter test` y ejecutable en un Isolate.

import 'package:flutter/foundation.dart';

/// Naturaleza del ejercicio: define cómo se registra y cómo progresa.
enum ExerciseKind {
  /// Carga externa (barra/mancuerna): progresa por peso.
  weighted,

  /// Peso corporal (flexiones, dominadas…): progresa por reps (o por lastre si hay).
  bodyweight,

  /// Isométrico/acarreos (plancha, farmer walk): se registra por tiempo.
  timed,

  /// Cardio: tiempo + velocidad, sin progresión de carga.
  cardio,
}

/// Regla de sobrecarga progresiva elegida por rutina (override por ejercicio).
enum ProgressionRuleType {
  linear,
  greyskullLP,
  doubleProgression,
  addTime,
  bodyweightReps,
}

/// Decisión del motor para la próxima sesión.
enum ProgressionAction {
  advanceWeight,
  advanceReps,
  advanceTime,
  addSet,
  hold,
  deload,
  start,
}

/// Una serie registrada.
@immutable
class SetLog {
  const SetLog({
    this.weightKg = 0,
    this.reps = 0,
    this.timeSec,
    this.rir,
    this.rpe,
    this.completed = true,
  });

  /// Carga EXTERNA en kg. En bodyweight sin lastre es 0.
  final double weightKg;

  /// Repeticiones TOTALES (si es "por lado", el total de ambos lados).
  final int reps;

  /// Segundos sostenidos (solo ejercicios cronometrados).
  final int? timeSec;

  /// Esfuerzo opcional. Nunca afecta a progresión ni 1RM (openGym: "nothing else
  /// reads the value"). Cada serie conserva su propia escala.
  final double? rir;
  final double? rpe;

  /// ¿La serie se completó según lo previsto? Una serie fallada no avanza carga.
  final bool completed;

  bool get isTimed => timeSec != null;

  SetLog copyWith({
    double? weightKg,
    int? reps,
    int? timeSec,
    double? rir,
    double? rpe,
    bool? completed,
  }) {
    return SetLog(
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      timeSec: timeSec ?? this.timeSec,
      rir: rir ?? this.rir,
      rpe: rpe ?? this.rpe,
      completed: completed ?? this.completed,
    );
  }
}

/// Todas las series de UN ejercicio en UNA sesión.
@immutable
class ExerciseSession {
  const ExerciseSession({required this.date, required this.sets});

  final DateTime date;
  final List<SetLog> sets;

  /// Serie de trabajo más pesada realmente completada (base para progresar).
  double get topWeightKg {
    double w = 0;
    for (final s in sets) {
      if (s.completed && s.weightKg > w) w = s.weightKg;
    }
    return w;
  }

  /// Reps de la última serie (AMRAP top set en Greyskull).
  int get topSetReps => sets.isEmpty ? 0 : sets.last.reps;
}

/// Configuración de la regla de progresión para un ejercicio.
@immutable
class ProgressionConfig {
  const ProgressionConfig({
    required this.rule,
    required this.kind,
    this.targetSets = 3,
    this.repMin = 5,
    this.repMax = 8,
    this.incrementKg = 2.5,
    this.stallLimit = 3,
    this.deloadPct = 0.10,
    this.roundingKg = 2.5,
    this.repCeiling = 20,
    this.timeIncrementSec = 5,
    this.timeTargetSec = 30,
    this.perSide = false,
    this.startWeightKg = 0,
  });

  final ProgressionRuleType rule;
  final ExerciseKind kind;

  /// Series objetivo por sesión.
  final int targetSets;

  /// Rango de reps. En lineal/greyskull, `repMin` es el objetivo por serie.
  final int repMin;
  final int repMax;

  /// Salto de carga cuando se avanza.
  final double incrementKg;

  /// Sesiones consecutivas estancadas antes de forzar un deload.
  final int stallLimit;

  /// Fracción de descarga (0.10 = -10%).
  final double deloadPct;

  /// Incremento mínimo de barra (para redondear el peso objetivo).
  final double roundingKg;

  /// Bodyweight: tope de reps antes de añadir una SERIE en vez de una repetición.
  final int repCeiling;

  /// Ejercicios cronometrados.
  final int timeIncrementSec;
  final int timeTargetSec;

  /// Reps por lado: el objetivo avanza de dos en dos (nunca cae en impar).
  final bool perSide;

  /// Carga inicial sugerida en la primerísima sesión.
  final double startWeightKg;
}

/// Objetivo calculado para la PRÓXIMA sesión, con el "porqué" del número.
@immutable
class ProgressionTarget {
  const ProgressionTarget({
    required this.action,
    required this.reason,
    this.weightKg,
    this.reps,
    this.repsPerSide,
    this.sets,
    this.timeSec,
  });

  final ProgressionAction action;

  /// Explicación legible ("Completaste 3×5 → +2.5 kg"). openGym: "every target
  /// says why it's that number".
  final String reason;

  final double? weightKg;
  final int? reps;
  final int? repsPerSide;
  final int? sets;
  final int? timeSec;
}
