// @file test/features/workout/training/session_builder_test.dart
// Ejecutar: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_mobile_app/features/workout/domain/entities/workout_entities.dart';
import 'package:gym_mobile_app/features/workout/domain/training/set_log.dart';
import 'package:gym_mobile_app/features/workout/domain/training/session_builder.dart';

WorkoutExercise _ex(String nombre, {int series = 3, String reps = '8-12'}) =>
    WorkoutExercise(
      ejercicioId: 'wger-001',
      nombre: nombre,
      musculos_primarios: const [],
      musculos_secundarios: const [],
      series: series,
      repeticiones: reps,
    );

void main() {
  group('parseRepRange', () {
    test('rango "8-12"', () {
      final r = parseRepRange('8-12');
      expect(r.min, 8);
      expect(r.max, 12);
    });
    test('valor único "10"', () {
      final r = parseRepRange('10');
      expect(r.min, 10);
      expect(r.max, 10);
    });
    test('texto sin números → fallback', () {
      final r = parseRepRange('AMRAP');
      expect(r.min, 8);
      expect(r.max, 12);
    });
    test('desordenado "12-8" se normaliza', () {
      final r = parseRepRange('12-8');
      expect(r.min, 8);
      expect(r.max, 12);
    });
  });

  group('inferExerciseKind', () {
    test('plancha → timed', () {
      expect(inferExerciseKind('Plancha abdominal'), ExerciseKind.timed);
    });
    test('flexiones → bodyweight', () {
      expect(inferExerciseKind('Flexiones de pecho'), ExerciseKind.bodyweight);
    });
    test('press banca → weighted', () {
      expect(inferExerciseKind('Press de Banca con Barra'), ExerciseKind.weighted);
    });
    test('farmer carry → timed', () {
      expect(inferExerciseKind("Farmer's Carry"), ExerciseKind.timed);
    });
  });

  group('inferPerSide', () {
    test('zancada búlgara → por lado', () {
      expect(inferPerSide('Zancada Búlgara'), isTrue);
    });
    test('press banca → no', () {
      expect(inferPerSide('Press de Banca'), isFalse);
    });
  });

  group('buildGuidedExercise', () {
    test('sin historial → objetivo inicial con reps del plan', () {
      final plan = buildGuidedExercise(
        _ex('Press de Banca', reps: '5'),
        objetivo: 'fuerza',
        history: const [],
      );
      expect(plan.config.rule, ProgressionRuleType.linear);
      expect(plan.target.action, ProgressionAction.start);
      expect(plan.target.reps, 5);
    });

    test('con historial exitoso (fuerza/lineal) → sube peso', () {
      final hist = [
        ExerciseSession(date: DateTime(2026, 1, 1), sets: const [
          SetLog(weightKg: 60, reps: 5),
          SetLog(weightKg: 60, reps: 5),
          SetLog(weightKg: 60, reps: 5),
        ]),
      ];
      final plan = buildGuidedExercise(
        _ex('Press de Banca', series: 3, reps: '5'),
        objetivo: 'fuerza',
        history: hist,
      );
      expect(plan.target.action, ProgressionAction.advanceWeight);
      expect(plan.target.weightKg, 62.5);
    });

    test('bodyweight infiere regla de reps', () {
      final plan = buildGuidedExercise(
        _ex('Dominadas', reps: '8-12'),
        objetivo: 'hipertrofia',
        history: const [],
      );
      expect(plan.config.kind, ExerciseKind.bodyweight);
      expect(plan.config.rule, ProgressionRuleType.bodyweightReps);
    });
  });
}
