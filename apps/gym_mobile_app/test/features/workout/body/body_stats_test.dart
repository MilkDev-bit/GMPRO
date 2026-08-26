// @file test/features/workout/body/body_stats_test.dart
// Ejecutar: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_mobile_app/features/workout/domain/body/body_weight.dart';
import 'package:gym_mobile_app/features/workout/domain/body/activity_heatmap.dart';

void main() {
  group('WeightSeries — dirección respecto a la meta', () {
    test('bajar hacia una meta menor = towardGoal', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 85),
        WeightEntry(date: DateTime(2026, 1, 2), kg: 84),
      ], goalKg: 80);
      expect(s.deltaAt(1).direction, WeightTrendDirection.towardGoal);
      expect(s.deltaAt(1).isLoss, isTrue);
    });

    test('subir alejándose de una meta menor = awayFromGoal', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 85),
        WeightEntry(date: DateTime(2026, 1, 2), kg: 86),
      ], goalKg: 80);
      expect(s.deltaAt(1).direction, WeightTrendDirection.awayFromGoal);
    });

    test('bulk: subir hacia una meta mayor = towardGoal', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 70),
        WeightEntry(date: DateTime(2026, 1, 2), kg: 71),
      ], goalKg: 78);
      expect(s.deltaAt(1).direction, WeightTrendDirection.towardGoal);
    });

    test('sin meta = neutral', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 70),
        WeightEntry(date: DateTime(2026, 1, 2), kg: 71),
      ]);
      expect(s.deltaAt(1).direction, WeightTrendDirection.neutral);
    });

    test('remainingToGoal y totalChange', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 85),
        WeightEntry(date: DateTime(2026, 1, 10), kg: 82),
      ], goalKg: 80);
      expect(s.totalChangeKg, closeTo(-3, 0.001));
      expect(s.remainingToGoalKg, closeTo(-2, 0.001)); // faltan 2kg por bajar
    });

    test('upsert reemplaza la entrada del mismo día', () {
      var s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 85),
      ]);
      s = s.upsert(WeightEntry(date: DateTime(2026, 1, 1), kg: 84.5));
      expect(s.entries.length, 1);
      expect(s.latest!.kg, 84.5);
    });

    test('media móvil de 7 días suaviza', () {
      final s = WeightSeries([
        WeightEntry(date: DateTime(2026, 1, 1), kg: 80),
        WeightEntry(date: DateTime(2026, 1, 2), kg: 82),
      ]);
      final ma = s.movingAverage(window: 7);
      expect(ma[0], 80);
      expect(ma[1], 81); // (80+82)/2
    });
  });

  group('Heatmap', () {
    test('intensityLevel escala 0..4', () {
      expect(intensityLevel(0, 100), 0);
      expect(intensityLevel(20, 100), 1);
      expect(intensityLevel(40, 100), 2);
      expect(intensityLevel(70, 100), 3);
      expect(intensityLevel(100, 100), 4);
    });

    test('agrega minutos por día y cuenta días activos', () {
      final recs = [
        ActivityRecord(date: DateTime(2026, 1, 5), minutes: 30),
        ActivityRecord(date: DateTime(2026, 1, 5), minutes: 20), // mismo día → 50
        ActivityRecord(date: DateTime(2026, 1, 7), minutes: 45),
      ];
      final hm = buildHeatmap(recs,
          from: DateTime(2026, 1, 5), to: DateTime(2026, 1, 11));
      expect(hm.totalMinutes, 95);
      expect(hm.activeDays, 2);
      expect(hm.maxMinutes, 50);
      // Una sola semana (lun 5 ene → dom 11 ene) de 7 celdas.
      expect(hm.weeks.length, 1);
      expect(hm.weeks.first.length, 7);
    });

    test('celdas fuera de rango marcadas inRange=false', () {
      // from = miércoles → lunes y martes previos quedan fuera de rango.
      final hm = buildHeatmap(const [],
          from: DateTime(2026, 1, 7), to: DateTime(2026, 1, 7));
      final week = hm.weeks.first;
      expect(week[0].inRange, isFalse); // lunes 5
      expect(week[2].inRange, isTrue); // miércoles 7
    });
  });
}
