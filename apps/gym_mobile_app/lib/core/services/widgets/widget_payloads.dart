/// @file lib/core/services/widgets/widget_payloads.dart
/// @description Estructuras y payloads para sincronización con WidgetKit (iOS App Groups),
/// Android AppWidgets (SharedPreferences) y ActivityKit (Live Activities).

import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Payload con el desglose de calorías y macronutrientes (Proteínas, Carbs, Grasas)
/// para renderizar en el widget mediano estilo Fitia.
class MacrosWidgetPayload extends Equatable {
  final int caloriesCurrent;
  final int caloriesTarget;
  final double proteinCurrent;
  final double proteinTarget;
  final double carbsCurrent;
  final double carbsTarget;
  final double fatCurrent;
  final double fatTarget;
  final String timestampIso;

  const MacrosWidgetPayload({
    required this.caloriesCurrent,
    required this.caloriesTarget,
    required this.proteinCurrent,
    required this.proteinTarget,
    required this.carbsCurrent,
    required this.carbsTarget,
    required this.fatCurrent,
    required this.fatTarget,
    required this.timestampIso,
  });

  Map<String, dynamic> toMap() {
    return {
      'calories_current': caloriesCurrent,
      'calories_target': caloriesTarget,
      'protein_current': proteinCurrent,
      'protein_target': proteinTarget,
      'carbs_current': carbsCurrent,
      'carbs_target': carbsTarget,
      'fat_current': fatCurrent,
      'fat_target': fatTarget,
      'timestamp_iso': timestampIso,
    };
  }

  factory MacrosWidgetPayload.fromMap(Map<String, dynamic> map) {
    return MacrosWidgetPayload(
      caloriesCurrent: map['calories_current'] as int? ?? 0,
      caloriesTarget: map['calories_target'] as int? ?? 2200,
      proteinCurrent: (map['protein_current'] as num?)?.toDouble() ?? 0.0,
      proteinTarget: (map['protein_target'] as num?)?.toDouble() ?? 160.0,
      carbsCurrent: (map['carbs_current'] as num?)?.toDouble() ?? 0.0,
      carbsTarget: (map['carbs_target'] as num?)?.toDouble() ?? 240.0,
      fatCurrent: (map['fat_current'] as num?)?.toDouble() ?? 0.0,
      fatTarget: (map['fat_target'] as num?)?.toDouble() ?? 65.0,
      timestampIso: map['timestamp_iso'] as String? ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  String toJson() => json.encode(toMap());

  @override
  List<Object?> get props => [
        caloriesCurrent,
        caloriesTarget,
        proteinCurrent,
        proteinTarget,
        carbsCurrent,
        carbsTarget,
        fatCurrent,
        fatTarget,
        timestampIso,
      ];
}

/// Payload para inicializar, actualizar o finalizar una Actividad en Vivo (Live Activity)
/// en iPhone (Pantalla de Bloqueo e Isla Dinámica).
class RestTimerLiveActivityPayload extends Equatable {
  final String activityId;
  final String exerciseName;
  final int currentSeries;
  final int totalSeries;
  final int restDurationSeconds;
  final String endTimeIso;
  final bool isResting;

  const RestTimerLiveActivityPayload({
    required this.activityId,
    required this.exerciseName,
    required this.currentSeries,
    required this.totalSeries,
    required this.restDurationSeconds,
    required this.endTimeIso,
    this.isResting = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'activity_id': activityId,
      'exercise_name': exerciseName,
      'current_series': currentSeries,
      'total_series': totalSeries,
      'rest_duration_seconds': restDurationSeconds,
      'end_time_iso': endTimeIso,
      'is_resting': isResting,
    };
  }

  factory RestTimerLiveActivityPayload.fromMap(Map<String, dynamic> map) {
    return RestTimerLiveActivityPayload(
      activityId: map['activity_id'] as String? ?? 'rest_timer_01',
      exerciseName: map['exercise_name'] as String? ?? 'Descanso',
      currentSeries: map['current_series'] as int? ?? 1,
      totalSeries: map['total_series'] as int? ?? 3,
      restDurationSeconds: map['rest_duration_seconds'] as int? ?? 90,
      endTimeIso: map['end_time_iso'] as String? ?? DateTime.now().add(const Duration(seconds: 90)).toUtc().toIso8601String(),
      isResting: map['is_resting'] as bool? ?? true,
    );
  }

  String toJson() => json.encode(toMap());

  @override
  List<Object?> get props => [
        activityId,
        exerciseName,
        currentSeries,
        totalSeries,
        restDurationSeconds,
        endTimeIso,
        isResting,
      ];
}
