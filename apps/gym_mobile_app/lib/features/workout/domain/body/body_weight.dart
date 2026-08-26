/// @file lib/features/workout/domain/body/body_weight.dart
/// @description Dominio PURO del seguimiento de peso corporal (port de openGym).
/// Una entrada por día, una meta opcional, y la lógica de "¿este cambio me acerca
/// o me aleja de la meta?" para colorear ganancias/pérdidas. Sin Flutter → testeable.

import 'package:flutter/foundation.dart';

/// Una medición de peso en una fecha (se normaliza a día, sin hora).
@immutable
class WeightEntry {
  WeightEntry({required DateTime date, required this.kg})
      : date = DateTime(date.year, date.month, date.day);

  final DateTime date;
  final double kg;

  WeightEntry copyWith({DateTime? date, double? kg}) =>
      WeightEntry(date: date ?? this.date, kg: kg ?? this.kg);
}

/// Dirección de un cambio de peso respecto a la meta.
enum WeightTrendDirection {
  towardGoal, // mejora: se acerca a la meta
  awayFromGoal, // empeora: se aleja
  neutral, // sin cambio o sin meta
}

/// Resultado de comparar una entrada con la anterior, dada una meta.
@immutable
class WeightDelta {
  const WeightDelta({
    required this.deltaKg,
    required this.direction,
  });

  /// Cambio respecto a la entrada previa (+ sube, − baja).
  final double deltaKg;
  final WeightTrendDirection direction;

  bool get isGain => deltaKg > 0;
  bool get isLoss => deltaKg < 0;
}

/// Serie de peso ordenada + operaciones de análisis. Inmutable.
@immutable
class WeightSeries {
  const WeightSeries(this.entries, {this.goalKg});

  /// Entradas ordenadas de más ANTIGUA a más RECIENTE (una por día).
  final List<WeightEntry> entries;

  /// Meta opcional fijada por el usuario.
  final double? goalKg;

  bool get isEmpty => entries.isEmpty;
  WeightEntry? get latest => entries.isEmpty ? null : entries.last;
  WeightEntry? get first => entries.isEmpty ? null : entries.first;

  double get minKg =>
      entries.isEmpty ? 0 : entries.map((e) => e.kg).reduce((a, b) => a < b ? a : b);
  double get maxKg =>
      entries.isEmpty ? 0 : entries.map((e) => e.kg).reduce((a, b) => a > b ? a : b);

  /// Cambio total desde la primera entrada.
  double? get totalChangeKg =>
      entries.length < 2 ? null : entries.last.kg - entries.first.kg;

  /// ¿Cuánto falta para la meta desde la última entrada? (+ hay que subir, − bajar).
  double? get remainingToGoalKg {
    if (goalKg == null || latest == null) return null;
    return goalKg! - latest!.kg;
  }

  /// Clasifica el cambio de la entrada [index] respecto a la [index-1].
  ///
  /// Con meta: baja hacia una meta menor = mejora; subir hacia una meta mayor
  /// (bulk) también = mejora. Sin meta: neutral (no hay "bueno/malo").
  WeightDelta deltaAt(int index) {
    if (index <= 0 || index >= entries.length) {
      return const WeightDelta(deltaKg: 0, direction: WeightTrendDirection.neutral);
    }
    final prev = entries[index - 1].kg;
    final curr = entries[index].kg;
    final delta = curr - prev;

    if (goalKg == null || delta == 0) {
      return WeightDelta(deltaKg: delta, direction: WeightTrendDirection.neutral);
    }

    // Distancia a la meta antes y después: si se redujo, va hacia la meta.
    final before = (goalKg! - prev).abs();
    final after = (goalKg! - curr).abs();
    final dir = after < before
        ? WeightTrendDirection.towardGoal
        : after > before
            ? WeightTrendDirection.awayFromGoal
            : WeightTrendDirection.neutral;
    return WeightDelta(deltaKg: delta, direction: dir);
  }

  /// Media móvil simple (suaviza el ruido diario del peso). Ventana en días.
  /// Devuelve una lista alineada con `entries` (mismo largo).
  List<double> movingAverage({int window = 7}) {
    final n = entries.length;
    final out = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final start = (i - window + 1) < 0 ? 0 : (i - window + 1);
      double sum = 0;
      for (int j = start; j <= i; j++) {
        sum += entries[j].kg;
      }
      out[i] = sum / (i - start + 1);
    }
    return out;
  }

  /// Añade o REEMPLAZA la entrada de un día (una medición por día) y reordena.
  WeightSeries upsert(WeightEntry entry) {
    final map = <String, WeightEntry>{
      for (final e in entries) _key(e.date): e,
    };
    map[_key(entry.date)] = entry;
    final list = map.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return WeightSeries(list, goalKg: goalKg);
  }

  WeightSeries withGoal(double? kg) => WeightSeries(entries, goalKg: kg);

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
