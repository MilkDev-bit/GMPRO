/// @file lib/features/workout/domain/training/progression.dart
/// @description Motor de sobrecarga progresiva. Dada la configuración de la regla
/// y el historial de sesiones de UN ejercicio, calcula el objetivo de la PRÓXIMA
/// sesión (peso/reps/tiempo) con una razón legible.
///
/// INVARIANTES (openGym): las reps falladas NUNCA avanzan la carga; el
/// estancamiento dispara un deload; el bodyweight progresa en reps.
///
/// Función pura: mismos argumentos → mismo resultado. Sin estado ni I/O.

import 'set_log.dart';

/// Redondea un peso al incremento de barra más cercano (p. ej. 2.5 kg).
double roundToIncrement(double weightKg, double increment) {
  if (increment <= 0) return weightKg;
  return (weightKg / increment).round() * increment;
}

/// Objetivo de reps "par" para ejercicios por lado (nunca cae en impar).
int _evenTarget(int reps) => reps.isEven ? reps : reps + 1;

/// Calcula el objetivo de la próxima sesión.
///
/// [history] va de la más ANTIGUA a la más RECIENTE.
ProgressionTarget nextTarget({
  required ProgressionConfig cfg,
  required List<ExerciseSession> history,
}) {
  // ── Primera sesión: no hay historial de qué progresar ─────────────────────
  if (history.isEmpty) {
    return _startTarget(cfg);
  }
  final last = history.last;

  switch (cfg.rule) {
    case ProgressionRuleType.linear:
      return _linear(cfg, history, last);
    case ProgressionRuleType.greyskullLP:
      return _greyskull(cfg, history, last);
    case ProgressionRuleType.doubleProgression:
      return _doubleProgression(cfg, last);
    case ProgressionRuleType.addTime:
      return _addTime(cfg, last);
    case ProgressionRuleType.bodyweightReps:
      return _bodyweightReps(cfg, last);
  }
}

// ── Objetivo inicial ─────────────────────────────────────────────────────────
ProgressionTarget _startTarget(ProgressionConfig cfg) {
  switch (cfg.kind) {
    case ExerciseKind.timed:
      return ProgressionTarget(
        action: ProgressionAction.start,
        reason: 'Primera sesión: sostén ${cfg.timeTargetSec}s.',
        timeSec: cfg.timeTargetSec,
        sets: cfg.targetSets,
      );
    case ExerciseKind.bodyweight:
      final reps = cfg.perSide ? _evenTarget(cfg.repMin) : cfg.repMin;
      return ProgressionTarget(
        action: ProgressionAction.start,
        reason: 'Primera sesión: apunta a ${cfg.targetSets}×$reps.',
        reps: reps,
        repsPerSide: cfg.perSide ? reps ~/ 2 : null,
        sets: cfg.targetSets,
      );
    case ExerciseKind.weighted:
    case ExerciseKind.cardio:
      final reps = cfg.perSide ? _evenTarget(cfg.repMin) : cfg.repMin;
      return ProgressionTarget(
        action: ProgressionAction.start,
        reason: 'Primera sesión: ${cfg.targetSets}×$reps a peso cómodo.',
        weightKg: cfg.startWeightKg,
        reps: reps,
        repsPerSide: cfg.perSide ? reps ~/ 2 : null,
        sets: cfg.targetSets,
      );
  }
}

// ── ¿Se cumplió el objetivo de reps en TODAS las series de trabajo? ──────────
bool _hitAllReps(ExerciseSession s, int targetReps, int targetSets) {
  final working = s.sets.where((x) => x.completed).toList();
  if (working.length < targetSets) return false;
  return working.every((x) => x.reps >= targetReps);
}

/// Cuenta sesiones consecutivas (desde el final) que NO cumplieron el objetivo.
int _consecutiveStalls(
  List<ExerciseSession> history,
  int targetReps,
  int targetSets,
) {
  int count = 0;
  for (int i = history.length - 1; i >= 0; i--) {
    if (_hitAllReps(history[i], targetReps, targetSets)) break;
    count++;
  }
  return count;
}

int? _perSide(ProgressionConfig cfg, int reps) => cfg.perSide ? reps ~/ 2 : null;

// ── LINEAL ───────────────────────────────────────────────────────────────────
ProgressionTarget _linear(
  ProgressionConfig cfg,
  List<ExerciseSession> history,
  ExerciseSession last,
) {
  final target = cfg.perSide ? _evenTarget(cfg.repMin) : cfg.repMin;
  final lastW = last.topWeightKg;

  if (_hitAllReps(last, target, cfg.targetSets)) {
    final next = roundToIncrement(lastW + cfg.incrementKg, cfg.roundingKg);
    return ProgressionTarget(
      action: ProgressionAction.advanceWeight,
      reason: 'Completaste ${cfg.targetSets}×$target → +${cfg.incrementKg} kg.',
      weightKg: next,
      reps: target,
      repsPerSide: _perSide(cfg, target),
      sets: cfg.targetSets,
    );
  }

  final stalls = _consecutiveStalls(history, target, cfg.targetSets);
  if (stalls >= cfg.stallLimit) {
    final next = roundToIncrement(lastW * (1 - cfg.deloadPct), cfg.roundingKg);
    return ProgressionTarget(
      action: ProgressionAction.deload,
      reason:
          '$stalls sesiones estancado → deload ${(cfg.deloadPct * 100).round()}% '
          '(${lastW.toStringAsFixed(1)} → ${next.toStringAsFixed(1)} kg).',
      weightKg: next,
      reps: target,
      repsPerSide: _perSide(cfg, target),
      sets: cfg.targetSets,
    );
  }

  return ProgressionTarget(
    action: ProgressionAction.hold,
    reason: 'No cerraste todas las series → repite ${lastW.toStringAsFixed(1)} kg.',
    weightKg: lastW,
    reps: target,
    repsPerSide: _perSide(cfg, target),
    sets: cfg.targetSets,
  );
}

// ── GREYSKULL LP (AMRAP en la última serie, doble salto, reset 10%) ──────────
ProgressionTarget _greyskull(
  ProgressionConfig cfg,
  List<ExerciseSession> history,
  ExerciseSession last,
) {
  final target = cfg.repMin;
  final lastW = last.topWeightKg;
  final amrap = last.topSetReps; // reps de la serie AMRAP final
  final allWorkingDone =
      last.sets.where((x) => x.completed).length >= cfg.targetSets;

  // Doble salto si en la AMRAP dobla el objetivo (openGym: "double jumps").
  if (allWorkingDone && amrap >= target * 2) {
    final next = roundToIncrement(lastW + cfg.incrementKg * 2, cfg.roundingKg);
    return ProgressionTarget(
      action: ProgressionAction.advanceWeight,
      reason: 'AMRAP $amrap ≥ ${target * 2} → doble salto +${cfg.incrementKg * 2} kg.',
      weightKg: next,
      reps: target,
      sets: cfg.targetSets,
    );
  }

  // Salto simple si alcanzaste el objetivo en la AMRAP.
  if (allWorkingDone && amrap >= target) {
    final next = roundToIncrement(lastW + cfg.incrementKg, cfg.roundingKg);
    return ProgressionTarget(
      action: ProgressionAction.advanceWeight,
      reason: 'AMRAP $amrap ≥ $target → +${cfg.incrementKg} kg.',
      weightKg: next,
      reps: target,
      sets: cfg.targetSets,
    );
  }

  // Fallo: Greyskull resetea el 10% (openGym: "10 % resets").
  final next = roundToIncrement(lastW * (1 - cfg.deloadPct), cfg.roundingKg);
  return ProgressionTarget(
    action: ProgressionAction.deload,
    reason:
        'Fallaste el objetivo ($amrap < $target) → reset ${(cfg.deloadPct * 100).round()}% '
        '(${lastW.toStringAsFixed(1)} → ${next.toStringAsFixed(1)} kg).',
    weightKg: next,
    reps: target,
    sets: cfg.targetSets,
  );
}

// ── DOBLE PROGRESIÓN (sube reps dentro del rango; al techo, sube peso) ───────
ProgressionTarget _doubleProgression(ProgressionConfig cfg, ExerciseSession last) {
  final lastW = last.topWeightKg;
  final hitTop = _hitAllReps(last, cfg.repMax, cfg.targetSets);

  if (hitTop) {
    final next = roundToIncrement(lastW + cfg.incrementKg, cfg.roundingKg);
    final bottom = cfg.perSide ? _evenTarget(cfg.repMin) : cfg.repMin;
    return ProgressionTarget(
      action: ProgressionAction.advanceWeight,
      reason:
          'Alcanzaste ${cfg.repMax} reps en todas → +${cfg.incrementKg} kg y baja a $bottom.',
      weightKg: next,
      reps: bottom,
      repsPerSide: _perSide(cfg, bottom),
      sets: cfg.targetSets,
    );
  }

  // Mantener peso y perseguir el techo de reps.
  final topReps = cfg.perSide ? _evenTarget(cfg.repMax) : cfg.repMax;
  return ProgressionTarget(
    action: ProgressionAction.advanceReps,
    reason: 'Sube reps hasta ${cfg.repMax} antes de subir peso.',
    weightKg: lastW,
    reps: topReps,
    repsPerSide: _perSide(cfg, topReps),
    sets: cfg.targetSets,
  );
}

// ── AÑADIR TIEMPO (isométricos / acarreos) ───────────────────────────────────
ProgressionTarget _addTime(ProgressionConfig cfg, ExerciseSession last) {
  // Menor tiempo sostenido entre las series completadas.
  int? minHeld;
  for (final s in last.sets) {
    if (!s.completed || s.timeSec == null) continue;
    minHeld = (minHeld == null) ? s.timeSec : (s.timeSec! < minHeld! ? s.timeSec : minHeld);
  }
  final prevTarget = minHeld ?? cfg.timeTargetSec;

  if (minHeld != null && minHeld! >= cfg.timeTargetSec) {
    final next = prevTarget + cfg.timeIncrementSec;
    return ProgressionTarget(
      action: ProgressionAction.advanceTime,
      reason: 'Sostuviste ${minHeld}s ≥ ${cfg.timeTargetSec}s → +${cfg.timeIncrementSec}s.',
      timeSec: next,
      weightKg: last.topWeightKg, // los acarreos pueden llevar carga
      sets: cfg.targetSets,
    );
  }

  return ProgressionTarget(
    action: ProgressionAction.hold,
    reason: 'Aún no llegas a ${cfg.timeTargetSec}s → repite el objetivo.',
    timeSec: cfg.timeTargetSec,
    weightKg: last.topWeightKg,
    sets: cfg.targetSets,
  );
}

// ── BODYWEIGHT (progresa en reps; con lastre sigue el peso) ──────────────────
ProgressionTarget _bodyweightReps(ProgressionConfig cfg, ExerciseSession last) {
  // Con lastre (dip belt): la carga externa manda → progresión lineal por peso.
  if (last.topWeightKg > 0) {
    final target = cfg.perSide ? _evenTarget(cfg.repMin) : cfg.repMin;
    if (_hitAllReps(last, target, cfg.targetSets)) {
      final next = roundToIncrement(last.topWeightKg + cfg.incrementKg, cfg.roundingKg);
      return ProgressionTarget(
        action: ProgressionAction.advanceWeight,
        reason: 'Con lastre: completaste ${cfg.targetSets}×$target → +${cfg.incrementKg} kg.',
        weightKg: next,
        reps: target,
        repsPerSide: _perSide(cfg, target),
        sets: cfg.targetSets,
      );
    }
    return ProgressionTarget(
      action: ProgressionAction.hold,
      reason: 'Con lastre: repite ${last.topWeightKg.toStringAsFixed(1)} kg.',
      weightKg: last.topWeightKg,
      reps: target,
      repsPerSide: _perSide(cfg, target),
      sets: cfg.targetSets,
    );
  }

  // Sin lastre: reps máximas de la mejor serie completada.
  int best = 0;
  for (final s in last.sets) {
    if (s.completed && s.reps > best) best = s.reps;
  }
  final step = cfg.perSide ? 2 : 1;

  // Si tocaste el techo de reps, añade una SERIE en vez de una repetición.
  if (best >= cfg.repCeiling) {
    return ProgressionTarget(
      action: ProgressionAction.addSet,
      reason:
          'Llegaste a ${cfg.repCeiling} reps → añade una serie (${cfg.targetSets + 1} en total) '
          'o pasa a una variante más difícil / con lastre.',
      reps: cfg.repCeiling,
      repsPerSide: _perSide(cfg, cfg.repCeiling),
      sets: cfg.targetSets + 1,
    );
  }

  final nextReps = best + step;
  return ProgressionTarget(
    action: ProgressionAction.advanceReps,
    reason: 'Sin lastre: sube a $nextReps reps por serie.',
    reps: nextReps,
    repsPerSide: _perSide(cfg, nextReps),
    sets: cfg.targetSets,
  );
}
