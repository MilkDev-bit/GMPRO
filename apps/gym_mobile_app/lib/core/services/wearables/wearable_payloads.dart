/// @file lib/core/services/wearables/wearable_payloads.dart
/// @description Modelos y payloads serializables para comunicación con Apple Watch (WCSession)
/// y relojes Android Wear OS (DataClient / MessageClient) a través de watch_connectivity y MethodChannel.

import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Tipo de mensaje enviado o recibido en el reloj inteligente.
enum WearableMessageType {
  workoutSync,
  seriesCompleted,
  qrAccessSync,
  qrRequestFromWatch,
  heartRateStream,
}

/// Payload para sincronizar el ejercicio activo del PageView en la muñeca del usuario.
class WorkoutWearPayload extends Equatable {
  final String exerciseId;
  final String exerciseName;
  final int currentSeries;
  final int totalSeries;
  final String reps;
  final int restDurationSeconds;
  final double? weightKg;
  final bool isWorkoutActive;
  final String timestamp;

  const WorkoutWearPayload({
    required this.exerciseId,
    required this.exerciseName,
    required this.currentSeries,
    required this.totalSeries,
    required this.reps,
    this.restDurationSeconds = 90,
    this.weightKg,
    this.isWorkoutActive = true,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': 'workout_sync',
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'current_series': currentSeries,
      'total_series': totalSeries,
      'reps': reps,
      'rest_duration_seconds': restDurationSeconds,
      'weight_kg': weightKg,
      'is_workout_active': isWorkoutActive,
      'timestamp': timestamp,
    };
  }

  factory WorkoutWearPayload.fromMap(Map<String, dynamic> map) {
    return WorkoutWearPayload(
      exerciseId: map['exercise_id'] as String? ?? '',
      exerciseName: map['exercise_name'] as String? ?? 'Ejercicio',
      currentSeries: map['current_series'] as int? ?? 1,
      totalSeries: map['total_series'] as int? ?? 3,
      reps: map['reps']?.toString() ?? '10-12',
      restDurationSeconds: map['rest_duration_seconds'] as int? ?? 90,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      isWorkoutActive: map['is_workout_active'] as bool? ?? true,
      timestamp: map['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  String toJson() => json.encode(toMap());

  factory WorkoutWearPayload.fromJson(String source) =>
      WorkoutWearPayload.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        exerciseId,
        exerciseName,
        currentSeries,
        totalSeries,
        reps,
        restDurationSeconds,
        weightKg,
        isWorkoutActive,
        timestamp,
      ];
}

/// Payload para enviar el código QR dinámico de 30 segundos de acceso al torniquete
/// para que se muestre como un widget en la pantalla del reloj sin sacar el teléfono.
class QrAccessWearPayload extends Equatable {
  final String qrToken;
  final String expiresAtIso;
  final int refreshIntervalSeconds;
  final String userFullName;
  final String membershipTier;

  const QrAccessWearPayload({
    required this.qrToken,
    required this.expiresAtIso,
    this.refreshIntervalSeconds = 30,
    required this.userFullName,
    required this.membershipTier,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': 'qr_access_sync',
      'qr_token': qrToken,
      'expires_at': expiresAtIso,
      'refresh_interval_seconds': refreshIntervalSeconds,
      'user_full_name': userFullName,
      'membership_tier': membershipTier,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  factory QrAccessWearPayload.fromMap(Map<String, dynamic> map) {
    return QrAccessWearPayload(
      qrToken: map['qr_token'] as String? ?? '',
      expiresAtIso: map['expires_at'] as String? ?? DateTime.now().add(const Duration(seconds: 30)).toUtc().toIso8601String(),
      refreshIntervalSeconds: map['refresh_interval_seconds'] as int? ?? 30,
      userFullName: map['user_full_name'] as String? ?? 'Atleta GymPro',
      membershipTier: map['membership_tier'] as String? ?? 'PRO',
    );
  }

  String toJson() => json.encode(toMap());

  factory QrAccessWearPayload.fromJson(String source) =>
      QrAccessWearPayload.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [qrToken, expiresAtIso, refreshIntervalSeconds, userFullName, membershipTier];
}

/// Payload enviado desde el reloj al presionar el botón táctil "Serie Completada".
class SeriesCompletedWearAction extends Equatable {
  final String exerciseId;
  final int completedSeries;
  final String timestamp;
  final int? heartRateBpm;

  const SeriesCompletedWearAction({
    required this.exerciseId,
    required this.completedSeries,
    required this.timestamp,
    this.heartRateBpm,
  });

  factory SeriesCompletedWearAction.fromMap(Map<String, dynamic> map) {
    return SeriesCompletedWearAction(
      exerciseId: map['exercise_id'] as String? ?? '',
      completedSeries: map['completed_series'] as int? ?? 1,
      timestamp: map['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      heartRateBpm: map['heart_rate_bpm'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'action': 'series_completed',
        'exercise_id': exerciseId,
        'completed_series': completedSeries,
        'timestamp': timestamp,
        'heart_rate_bpm': heartRateBpm,
      };

  @override
  List<Object?> get props => [exerciseId, completedSeries, timestamp, heartRateBpm];
}
