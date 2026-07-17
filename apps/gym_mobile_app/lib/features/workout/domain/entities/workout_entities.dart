/// @file lib/features/workout/domain/entities/workout_entities.dart
/// @description Entidades del dominio para rutinas IA con datos anatómicos completos.

import 'package:flutter/foundation.dart';

// Funciones top-level requeridas por compute() para ejecutarse en un Isolate separado
WorkoutPlan _parseWorkoutPlanTopLevel(Map<String, dynamic> json) => WorkoutPlan.fromJson(json);
List<WorkoutExercise> _parseExerciseListTopLevel(List<dynamic> list) =>
    list.map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>)).toList();

/// Representa un ejercicio individual con músculos primarios/secundarios mapeados.
class WorkoutExercise {
  const WorkoutExercise({
    required this.ejercicioId,
    required this.nombre,
    required this.musculos_primarios,
    required this.musculos_secundarios,
    required this.series,
    required this.repeticiones,
    this.descansoSeg = 90,
    this.notas,
    this.videoUrl,
  });

  final String ejercicioId;
  final String nombre;
  final List<String> musculos_primarios;
  final List<String> musculos_secundarios;
  final int series;
  final String repeticiones;
  final int descansoSeg;
  final String? notas;
  final String? videoUrl;

  /// Todos los músculos implicados (primarios + secundarios)
  List<String> get allMuscles => [...musculos_primarios, ...musculos_secundarios];

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    return WorkoutExercise(
      ejercicioId:          json['ejercicio_id'] as String? ?? 'wger-000',
      nombre:               json['nombre'] as String? ?? 'Ejercicio',
      musculos_primarios:   _toStringList(json['musculos_primarios']),
      musculos_secundarios: _toStringList(json['musculos_secundarios']),
      series:               json['series'] as int? ?? 3,
      repeticiones:         json['repeticiones'] as String? ?? '10-12',
      descansoSeg:          json['descanso_seg'] as int? ?? 90,
      notas:                json['notas'] as String?,
      videoUrl:             json['video_url'] as String?,
    );
  }

  static List<String> _toStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  /// Parsea listas extensas de ejercicios en un hilo secundario/Isolate para evitar jank en la UI.
  static Future<List<WorkoutExercise>> parseListInBackground(List<dynamic> list) async {
    return compute(_parseExerciseListTopLevel, list);
  }
}

/// Representa un día de entrenamiento dentro del plan semanal.
class WorkoutDay {
  const WorkoutDay({
    required this.dia,
    required this.ejercicios,
    this.enfoqueMusculares = const [],
  });

  final String dia;
  final List<WorkoutExercise> ejercicios;
  final List<String> enfoqueMusculares;

  factory WorkoutDay.fromJson(Map<String, dynamic> json) {
    return WorkoutDay(
      dia: json['dia'] as String? ?? 'Día de Entrenamiento',
      ejercicios: (json['ejercicios'] as List<dynamic>? ?? [])
          .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      enfoqueMusculares: (json['enfoque_muscular'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Plan de rutina completo retornado por el ai-service.
class WorkoutPlan {
  const WorkoutPlan({
    required this.nombre,
    required this.descripcion,
    required this.nivel,
    required this.objetivo,
    required this.dias,
  });

  final String nombre;
  final String descripcion;
  final String nivel;
  final String objetivo;
  final List<WorkoutDay> dias;

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) {
    return WorkoutPlan(
      nombre:      json['nombre'] as String? ?? 'Plan de Entrenamiento',
      descripcion: json['descripcion'] as String? ?? '',
      nivel:       json['nivel'] as String? ?? 'intermedio',
      objetivo:    json['objetivo'] as String? ?? 'hipertrofia',
      dias:        (json['dias'] as List<dynamic>? ?? [])
          .map((e) => WorkoutDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parsea un mapa JSON gigante en un hilo secundario/Isolate usando compute()
  static Future<WorkoutPlan> parseInBackground(Map<String, dynamic> json) async {
    return compute(_parseWorkoutPlanTopLevel, json);
  }
}
