/// @file lib/features/workout/data/activity_store.dart
/// @description Registro local de sesiones (fecha + minutos) que alimenta el
/// heatmap de actividad. El runner guiado añade una entrada al finalizar.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/body/activity_heatmap.dart';

abstract class ActivityStore {
  Future<List<ActivityRecord>> load();
  Future<void> append(ActivityRecord record);
}

class SharedPrefsActivityStore implements ActivityStore {
  SharedPrefsActivityStore({this.maxRecords = 800});

  /// Tope de registros conservados (~2 años entrenando a diario).
  final int maxRecords;

  static const _key = 'gympro:activity:log';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<List<ActivityRecord>> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => ActivityRecord(
                date: DateTime.parse((e as Map<String, dynamic>)['d'] as String),
                minutes: (e['m'] as num).toInt(),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> append(ActivityRecord record) async {
    final prefs = await _prefs;
    final current = await load();
    final updated = [...current, record];
    final trimmed = updated.length > maxRecords
        ? updated.sublist(updated.length - maxRecords)
        : updated;
    await prefs.setString(
      _key,
      jsonEncode(
          trimmed.map((e) => {'d': e.date.toIso8601String(), 'm': e.minutes}).toList()),
    );
  }
}
