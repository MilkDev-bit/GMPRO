/// @file lib/features/workout/domain/body/activity_heatmap.dart
/// @description Agregación PURA para el heatmap de actividad estilo GitHub
/// (port de openGym). Convierte una lista de sesiones (fecha + minutos entrenados)
/// en una cuadrícula de semanas × 7 días con un nivel de intensidad por celda.

import 'package:flutter/foundation.dart';

/// Una sesión ya resumida a lo que importa para el heatmap.
@immutable
class ActivityRecord {
  ActivityRecord({required DateTime date, required this.minutes})
      : date = DateTime(date.year, date.month, date.day);

  final DateTime date;
  final int minutes;
}

/// Una celda del heatmap: un día concreto con su intensidad.
@immutable
class HeatmapCell {
  const HeatmapCell({
    required this.date,
    required this.minutes,
    required this.level,
    required this.inRange,
  });

  final DateTime date;
  final int minutes;

  /// 0 (sin actividad) … 4 (máxima intensidad).
  final int level;

  /// false para celdas de relleno fuera del rango [from, to] (alinear semanas).
  final bool inRange;
}

/// Cuadrícula lista para pintar: columnas = semanas, filas = 7 días (lun→dom).
@immutable
class Heatmap {
  const Heatmap({
    required this.weeks,
    required this.totalMinutes,
    required this.activeDays,
    required this.maxMinutes,
  });

  /// weeks[semana][díaDeLaSemana 0..6].
  final List<List<HeatmapCell>> weeks;
  final int totalMinutes;
  final int activeDays;
  final int maxMinutes;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lunes de la semana que contiene [d] (ISO: lunes = 1).
DateTime _mondayOf(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

/// Nivel de intensidad 0..4 a partir de los minutos y el máximo observado.
int intensityLevel(int minutes, int maxMinutes) {
  if (minutes <= 0) return 0;
  if (maxMinutes <= 0) return 1;
  final ratio = minutes / maxMinutes;
  if (ratio <= 0.25) return 1;
  if (ratio <= 0.5) return 2;
  if (ratio <= 0.75) return 3;
  return 4;
}

/// Construye el heatmap entre [from] y [to] (inclusive) agregando por día.
/// La cuadrícula empieza el lunes de la semana de [from] y termina el domingo
/// de la semana de [to], para que las columnas queden alineadas.
Heatmap buildHeatmap(
  List<ActivityRecord> records, {
  required DateTime from,
  required DateTime to,
}) {
  // 1. Sumar minutos por día (varias sesiones el mismo día se acumulan).
  final byDay = <String, int>{};
  int totalMinutes = 0;
  for (final r in records) {
    final k = _key(r.date);
    byDay[k] = (byDay[k] ?? 0) + r.minutes;
    totalMinutes += r.minutes;
  }
  final maxMinutes =
      byDay.values.isEmpty ? 0 : byDay.values.reduce((a, b) => a > b ? a : b);

  final start = _mondayOf(from);
  final endSunday = _mondayOf(to).add(const Duration(days: 6));

  final rangeFrom = _day(from);
  final rangeTo = _day(to);

  final weeks = <List<HeatmapCell>>[];
  int activeDays = 0;

  DateTime cursor = start;
  while (!cursor.isAfter(endSunday)) {
    final week = <HeatmapCell>[];
    for (int i = 0; i < 7; i++) {
      final day = cursor.add(Duration(days: i));
      final inRange = !day.isBefore(rangeFrom) && !day.isAfter(rangeTo);
      final minutes = inRange ? (byDay[_key(day)] ?? 0) : 0;
      if (inRange && minutes > 0) activeDays++;
      week.add(HeatmapCell(
        date: day,
        minutes: minutes,
        level: inRange ? intensityLevel(minutes, maxMinutes) : 0,
        inRange: inRange,
      ));
    }
    weeks.add(week);
    cursor = cursor.add(const Duration(days: 7));
  }

  return Heatmap(
    weeks: weeks,
    totalMinutes: totalMinutes,
    activeDays: activeDays,
    maxMinutes: maxMinutes,
  );
}

/// Vista de "último año" terminando hoy.
Heatmap buildYearHeatmap(List<ActivityRecord> records, {DateTime? today}) {
  final end = _day(today ?? DateTime.now());
  final start = end.subtract(const Duration(days: 364));
  return buildHeatmap(records, from: start, to: end);
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
