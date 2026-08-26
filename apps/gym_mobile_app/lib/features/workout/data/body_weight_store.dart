/// @file lib/features/workout/data/body_weight_store.dart
/// @description Persistencia local del peso corporal y la meta (SharedPreferences).
/// Local-first, sin backend. La interfaz permite cambiar a Isar/sync sin tocar la UI.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/body/body_weight.dart';

abstract class BodyWeightStore {
  Future<WeightSeries> load();
  Future<void> saveSeries(WeightSeries series);
}

class SharedPrefsBodyWeightStore implements BodyWeightStore {
  static const _entriesKey = 'gympro:bodyweight:entries';
  static const _goalKey = 'gympro:bodyweight:goal';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<WeightSeries> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_entriesKey);
    final goal = prefs.getDouble(_goalKey);

    if (raw == null || raw.isEmpty) {
      return WeightSeries(const [], goalKg: goal);
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => WeightEntry(
                date: DateTime.parse((e as Map<String, dynamic>)['d'] as String),
                kg: (e['kg'] as num).toDouble(),
              ))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      return WeightSeries(list, goalKg: goal);
    } catch (_) {
      return WeightSeries(const [], goalKg: goal);
    }
  }

  @override
  Future<void> saveSeries(WeightSeries series) async {
    final prefs = await _prefs;
    final encoded = jsonEncode(series.entries
        .map((e) => {'d': e.date.toIso8601String(), 'kg': e.kg})
        .toList());
    await prefs.setString(_entriesKey, encoded);
    if (series.goalKg == null) {
      await prefs.remove(_goalKey);
    } else {
      await prefs.setDouble(_goalKey, series.goalKg!);
    }
  }
}
