/// @file lib/core/offline/sync_manager.dart
/// @description Orquestador de sincronización offline→online.
///
/// Reglas respetadas:
///   • R1: servicio independiente, sin BuildContext. El transporte (a dónde se
///     envían las acciones) se INYECTA como callback → desacoplado de red/API.
///     Importante: por el RLS deny-all del backend, el ejecutor debe apuntar a
///     nuestros microservicios (ApiClient), NO a Supabase REST directo.
///   • R3: degradación graciosa — si el envío falla, la acción se conserva en la
///     cola (retry++), se atrapa la excepción y NUNCA se propaga a la UI.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'isar_service.dart';
import 'models/sync_action.dart';

/// Ejecuta UNA acción contra el backend. Debe LANZAR si falla (para reintentar).
typedef SyncExecutor = Future<void> Function(SyncAction action);

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  static const int maxRetries = 8;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  SyncExecutor? _executor;
  bool _draining = false;

  /// Inicializa el manager con el ejecutor de transporte (inyectado). Empieza a
  /// escuchar la red y hace un primer intento de drenado si ya hay conexión.
  Future<void> initialize({required SyncExecutor executor}) async {
    _executor = executor;
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      if (_isOnline(results)) _drainQueue();
    });
    if (_isOnline(await _connectivity.checkConnectivity())) {
      unawaited(_drainQueue());
    }
  }

  bool _isOnline(List<ConnectivityResult> r) =>
      r.isNotEmpty && !r.every((x) => x == ConnectivityResult.none);

  /// Encola una acción para sincronizar más tarde.
  Future<void> enqueue(String actionType, String payloadJson) {
    return IsarService.instance.put<SyncAction>(
      SyncAction.create(actionType: actionType, payloadJson: payloadJson),
    );
  }

  /// Patrón "intenta ahora; si falla, encola" (R3). Lo usan los repositorios:
  /// intenta ejecutar la acción de inmediato; ante CUALQUIER error la mete en la
  /// cola para reintento y no propaga la excepción.
  Future<void> executeOrEnqueue(String actionType, String payloadJson) async {
    final action = SyncAction.create(actionType: actionType, payloadJson: payloadJson);
    try {
      await _executor?.call(action);
    } catch (_) {
      await IsarService.instance.put<SyncAction>(action); // degradación graciosa
    }
  }

  /// Drena la cola: itera acciones pendientes, las envía y las borra al éxito.
  /// Reentrante-seguro: `_draining` evita solapamientos si llegan dos eventos
  /// de red casi simultáneos.
  Future<void> _drainQueue() async {
    final executor = _executor;
    if (executor == null || _draining || !IsarService.instance.isReady) return;
    _draining = true;
    try {
      final isar = IsarService.instance.db;
      final pending = await isar.collection<SyncAction>()
          .filter()
          .statusEqualTo(SyncStatus.pending)
          .or()
          .statusEqualTo(SyncStatus.failed)
          .findAll();

      for (final action in pending) {
        // Re-chequeo de red por si se cayó a mitad del drenado.
        if (!_isOnline(await _connectivity.checkConnectivity())) break;
        try {
          await executor(action);
          // Éxito → se borra de la cola (ya persistido en el backend).
          await IsarService.instance.deleteById<SyncAction>(action.id);
        } catch (e) {
          // Fallo → conservar y marcar para reintento (R3). Nunca propagar.
          action
            ..retryCount += 1
            ..lastAttemptAt = DateTime.now()
            ..lastError = e.toString()
            ..status = action.retryCount + 1 >= maxRetries
                ? SyncStatus.failed
                : SyncStatus.pending;
          await IsarService.instance.put<SyncAction>(action);
          if (kDebugMode) {
            debugPrint('[SyncManager] acción ${action.actionType} reintento '
                '${action.retryCount}/$maxRetries: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncManager] drenado abortado: $e');
    } finally {
      _draining = false;
    }
  }

  /// Fuerza un intento de sincronización manual (ej. pull-to-refresh).
  Future<void> syncNow() => _drainQueue();

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
