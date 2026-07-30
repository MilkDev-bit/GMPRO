/// @file lib/core/offline/models/sync_action.dart
/// @description Cola de sincronización offline. Cada fila = una acción que NO se
/// pudo enviar al backend (sin red/timeout) y debe reintentarse luego.
///
/// Ejemplo de contenido:
///   actionType = 'complete_workout'
///   payloadJson = '{"routineId":"r1","completedAt":"2026-07-24T10:00:00Z"}'
///
/// NOTA: tras editar esta colección, regenera el código:
///   dart run build_runner build --delete-conflicting-outputs

import 'package:isar_community/isar.dart';

part 'sync_action.g.dart';

/// Estado de una acción encolada.
enum SyncStatus { pending, syncing, failed }

@collection
class SyncAction {
  Id id = Isar.autoIncrement;

  /// Tipo de acción (discrimina el endpoint destino en el ejecutor).
  /// Indexado para consultar/filtrar por tipo si hace falta.
  @Index()
  late String actionType;

  /// Payload de la acción serializado como JSON (agnóstico al modelo).
  late String payloadJson;

  @Enumerated(EnumType.name)
  SyncStatus status = SyncStatus.pending;

  /// Nº de reintentos fallidos (para backoff / descartar tras N intentos).
  int retryCount = 0;

  /// Último error (solo para diagnóstico local; nunca se muestra al usuario).
  String? lastError;

  DateTime createdAt = DateTime.now();
  DateTime? lastAttemptAt;

  SyncAction();

  /// Constructor ergonómico para encolar una acción nueva.
  SyncAction.create({required this.actionType, required this.payloadJson});
}
