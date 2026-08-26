// @file test/features/workout/training/progression_test.dart
// Tests del motor de progresión + 1RM. Ejecutar: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_mobile_app/features/workout/domain/training/set_log.dart';
import 'package:gym_mobile_app/features/workout/domain/training/progression.dart';
import 'package:gym_mobile_app/features/workout/domain/training/one_rep_max.dart';

ExerciseSession _session(List<SetLog> sets) =>
    ExerciseSession(date: DateTime(2026, 1, 1), sets: sets);

void main() {
  group('roundToIncrement', () {
    test('redondea a múltiplos de 2.5', () {
      expect(roundToIncrement(61.2, 2.5), 62.5);
      expect(roundToIncrement(60.0, 2.5), 60.0);
      expect(roundToIncrement(58.9, 2.5), 60.0);
    });
  });

  group('1RM (Epley)', () {
    test('serie de 1 rep = el propio peso', () {
      expect(epley1RM(100, 1), 100);
    });
    test('100kg x 5 ≈ 116.7kg', () {
      expect(epley1RM(100, 5), closeTo(116.67, 0.1));
    });
    test('weightForReps es la inversa', () {
      final oneRm = epley1RM(100, 5);
      expect(weightForReps(oneRm, 5), closeTo(100, 0.01));
    });
    test('elige la mejor serie elegible e ignora reps > 12', () {
      final est = estimateOneRepMax([
        const SetLog(weightKg: 100, reps: 5),   // ~116.7
        const SetLog(weightKg: 90, reps: 10),   // ~120.0 (mejor)
        const SetLog(weightKg: 60, reps: 20),   // ignorada (>12)
      ]);
      expect(est, isNotNull);
      expect(est!.source.weightKg, 90);
      expect(est.estimateKg, closeTo(120, 0.1));
    });
    test('sin series con carga → null (bodyweight)', () {
      final est = estimateOneRepMax([const SetLog(weightKg: 0, reps: 15)]);
      expect(est, isNull);
    });
  });

  const linearCfg = ProgressionConfig(
    rule: ProgressionRuleType.linear,
    kind: ExerciseKind.weighted,
    targetSets: 3,
    repMin: 5,
    incrementKg: 2.5,
    stallLimit: 3,
    roundingKg: 2.5,
  );

  group('Progresión lineal', () {
    test('primera sesión → start con peso inicial', () {
      final t = nextTarget(cfg: linearCfg, history: []);
      expect(t.action, ProgressionAction.start);
      expect(t.reps, 5);
    });

    test('completa 3×5 → +2.5kg', () {
      final t = nextTarget(cfg: linearCfg, history: [
        _session(const [
          SetLog(weightKg: 60, reps: 5),
          SetLog(weightKg: 60, reps: 5),
          SetLog(weightKg: 60, reps: 5),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceWeight);
      expect(t.weightKg, 62.5);
    });

    test('falla reps → mantiene el peso', () {
      final t = nextTarget(cfg: linearCfg, history: [
        _session(const [
          SetLog(weightKg: 60, reps: 5),
          SetLog(weightKg: 60, reps: 4), // falló
          SetLog(weightKg: 60, reps: 3),
        ]),
      ]);
      expect(t.action, ProgressionAction.hold);
      expect(t.weightKg, 60);
    });

    test('3 sesiones estancadas → deload 10%', () {
      final stalled = _session(const [
        SetLog(weightKg: 60, reps: 4),
        SetLog(weightKg: 60, reps: 4),
        SetLog(weightKg: 60, reps: 3),
      ]);
      final t = nextTarget(cfg: linearCfg, history: [stalled, stalled, stalled]);
      expect(t.action, ProgressionAction.deload);
      expect(t.weightKg, 55.0); // 60 * 0.9 = 54 → redondeado a 2.5 = 55
    });
  });

  group('Greyskull LP', () {
    const cfg = ProgressionConfig(
      rule: ProgressionRuleType.greyskullLP,
      kind: ExerciseKind.weighted,
      targetSets: 3,
      repMin: 5,
      incrementKg: 2.5,
    );
    test('AMRAP dobla el objetivo → doble salto', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 40, reps: 5),
          SetLog(weightKg: 40, reps: 5),
          SetLog(weightKg: 40, reps: 10), // AMRAP = 10 ≥ 2×5
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceWeight);
      expect(t.weightKg, 45.0); // +5
    });
    test('AMRAP por debajo del objetivo → reset 10%', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 40, reps: 5),
          SetLog(weightKg: 40, reps: 5),
          SetLog(weightKg: 40, reps: 3), // AMRAP = 3 < 5
        ]),
      ]);
      expect(t.action, ProgressionAction.deload);
      expect(t.weightKg, 35.0); // 40*0.9=36 → redondeado a 2.5 = 35.0
    });
  });

  group('Doble progresión', () {
    const cfg = ProgressionConfig(
      rule: ProgressionRuleType.doubleProgression,
      kind: ExerciseKind.weighted,
      targetSets: 3,
      repMin: 8,
      repMax: 12,
      incrementKg: 2.5,
    );
    test('toca el techo (12) en todas → sube peso y baja a 8', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 20, reps: 12),
          SetLog(weightKg: 20, reps: 12),
          SetLog(weightKg: 20, reps: 12),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceWeight);
      expect(t.weightKg, 22.5);
      expect(t.reps, 8);
    });
    test('aún sin techo → mantiene peso y persigue 12 reps', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 20, reps: 10),
          SetLog(weightKg: 20, reps: 9),
          SetLog(weightKg: 20, reps: 8),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceReps);
      expect(t.weightKg, 20);
      expect(t.reps, 12);
    });
  });

  group('Bodyweight', () {
    const cfg = ProgressionConfig(
      rule: ProgressionRuleType.bodyweightReps,
      kind: ExerciseKind.bodyweight,
      targetSets: 3,
      repMin: 8,
      repCeiling: 20,
    );
    test('sin lastre → sube una repetición', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 0, reps: 12),
          SetLog(weightKg: 0, reps: 11),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceReps);
      expect(t.reps, 13); // best 12 + 1
    });
    test('en el techo → añade una serie', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 0, reps: 20),
          SetLog(weightKg: 0, reps: 20),
        ]),
      ]);
      expect(t.action, ProgressionAction.addSet);
      expect(t.sets, 4);
    });
    test('con lastre → vuelve a seguir el peso', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(weightKg: 10, reps: 8),
          SetLog(weightKg: 10, reps: 8),
          SetLog(weightKg: 10, reps: 8),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceWeight);
      expect(t.weightKg, closeTo(12.5, 0.01));
    });
  });

  group('Reps por lado', () {
    test('el objetivo avanza en pares (nunca impar)', () {
      const cfg = ProgressionConfig(
        rule: ProgressionRuleType.bodyweightReps,
        kind: ExerciseKind.bodyweight,
        targetSets: 3,
        repMin: 8,
        perSide: true,
      );
      final t = nextTarget(cfg: cfg, history: [
        _session(const [SetLog(weightKg: 0, reps: 12)]),
      ]);
      // best 12 → +2 (par) = 14, split 7 por lado
      expect(t.reps, 14);
      expect(t.repsPerSide, 7);
    });
  });

  group('Timed (add time)', () {
    const cfg = ProgressionConfig(
      rule: ProgressionRuleType.addTime,
      kind: ExerciseKind.timed,
      targetSets: 3,
      timeTargetSec: 30,
      timeIncrementSec: 5,
    );
    test('sostiene ≥ objetivo → +5s', () {
      final t = nextTarget(cfg: cfg, history: [
        _session(const [
          SetLog(timeSec: 30, reps: 0),
          SetLog(timeSec: 32, reps: 0),
        ]),
      ]);
      expect(t.action, ProgressionAction.advanceTime);
      expect(t.timeSec, 35); // min sostenido 30 + 5
    });
  });
}
