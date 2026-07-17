/// @file lib/core/services/wearables/wearable_service.dart
/// @description Servicio de dominio y datos para la comunicación bidireccional entre la app móvil
/// y relojes inteligentes (Apple Watch WCSession / Android Wear OS DataClient & MessageClient).

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import 'wearable_payloads.dart';

// ── 1. CONTRATO ABSTRACTO DE SERVICIO (Domain/Contract) ──────────────────────
abstract class WearableService {
  /// Inicializa los oyentes de mensajes y contexto nativo de Apple Watch / Wear OS.
  Future<void> initialize();

  /// Verificaciones de estado del reloj conectado.
  Future<bool> get isSupported;
  Future<bool> get isPaired;
  Future<bool> get isReachable;

  /// Sincroniza el ejercicio activo del PageView en el reloj inteligente del usuario.
  Future<void> syncActiveWorkout(WorkoutWearPayload payload);

  /// Sincroniza el código QR dinámico y sus datos de expiración con el widget del reloj.
  Future<void> syncDynamicQrToken(QrAccessWearPayload payload);

  /// Flujo continuo de mensajes entrantes desde el reloj.
  Stream<Map<String, dynamic>> get incomingMessages;

  /// Callback registrado para cuando el usuario presiona "Serie Completada" desde su muñeca.
  void setOnSeriesCompletedCallback(void Function(SeriesCompletedWearAction action) callback);

  /// Callback registrado cuando el reloj solicita un nuevo código QR de acceso.
  void setOnQrRequestedCallback(void Function() callback);
}

// ── 2. IMPLEMENTACIÓN CONCRETA (Data/Implementation) ─────────────────────────
class WearableServiceImpl implements WearableService {
  WearableServiceImpl._();
  static final WearableServiceImpl instance = WearableServiceImpl._();

  final WatchConnectivity _watch = WatchConnectivity();
  static const MethodChannel _nativeChannel = MethodChannel('com.gympro.wearables/sync');

  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  void Function(SeriesCompletedWearAction action)? _onSeriesCompletedCallback;
  void Function()? _onQrRequestedCallback;

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Escuchar mensajes del plugin watch_connectivity (WCSession / MessageClient)
      _watch.messageStream.listen((message) {
        debugPrint('⌚ [WearableService] Mensaje entrante de reloj: $message');
        _processIncomingMessage(message);
      }, onError: (error) {
        debugPrint('⚠️ [WearableService] Error en stream de reloj: $error');
      });

      // 2. Escuchar llamadas directas nativas por MethodChannel para alta prioridad
      _nativeChannel.setMethodCallHandler(_onMethodCall);

      _isInitialized = true;
      debugPrint('⌚ [WearableService] Inicializado en ${Platform.operatingSystem}');
    } catch (e, stack) {
      debugPrint('❌ [WearableService] Error al inicializar servicio de relojes: $e\n$stack');
    }
  }

  @override
  Future<bool> get isSupported async {
    try {
      return await _watch.isSupported;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> get isPaired async {
    try {
      return await _watch.isPaired;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> get isReachable async {
    try {
      return await _watch.isReachable;
    } catch (e) {
      return false;
    }
  }

  @override
  Stream<Map<String, dynamic>> get incomingMessages => _messageStreamController.stream;

  @override
  void setOnSeriesCompletedCallback(void Function(SeriesCompletedWearAction action) callback) {
    _onSeriesCompletedCallback = callback;
  }

  @override
  void setOnQrRequestedCallback(void Function() callback) {
    _onQrRequestedCallback = callback;
  }

  @override
  Future<void> syncActiveWorkout(WorkoutWearPayload payload) async {
    final map = payload.toMap();
    debugPrint('⌚ [WearableService] Sincronizando rutina en muñeca: ${payload.exerciseName} (Serie ${payload.currentSeries}/${payload.totalSeries})');

    // A. Actualizar Contexto Persistente (WCSession ApplicationContext / Wear DataClient)
    try {
      await _watch.updateApplicationContext(map);
    } catch (e) {
      debugPrint('⚠️ [Wearable] No se pudo actualizar applicationContext de rutina: $e');
    }

    // B. Enviar Mensaje Directo si el reloj está activo en primer plano
    try {
      if (await isReachable) {
        await _watch.sendMessage(map);
      }
    } catch (e) {
      debugPrint('ℹ️ [Wearable] Reloj no alcanzable en tiempo real para mensaje directo: $e');
    }

    // C. Canal nativo complementario para servicios en segundo plano de Android/iOS
    try {
      await _nativeChannel.invokeMethod('syncWorkout', map);
    } on PlatformException catch (e) {
      debugPrint('ℹ️ [Wearable] Canal nativo MethodChannel syncWorkout ignorado/no conectado: ${e.message}');
    }
  }

  @override
  Future<void> syncDynamicQrToken(QrAccessWearPayload payload) async {
    final map = payload.toMap();
    debugPrint('⌚ [WearableService] Sincronizando código QR en reloj inteligente (expira en 30s)...');

    try {
      await _watch.updateApplicationContext(map);
    } catch (e) {
      debugPrint('⚠️ [Wearable] No se pudo actualizar applicationContext de QR: $e');
    }

    try {
      if (await isReachable) {
        await _watch.sendMessage(map);
      }
    } catch (e) {
      debugPrint('ℹ️ [Wearable] Reloj no alcanzable en tiempo real para QR: $e');
    }

    try {
      await _nativeChannel.invokeMethod('syncQrToken', map);
    } on PlatformException catch (e) {
      debugPrint('ℹ️ [Wearable] Canal nativo MethodChannel syncQrToken ignorado/no conectado: ${e.message}');
    }
  }

  // ── Procesamiento de Mensajes Entrantes ────────────────────────────────────

  void _processIncomingMessage(Map<String, dynamic> message) {
    _messageStreamController.add(message);

    final action = message['action']?.toString();
    final type = message['type']?.toString();

    if (action == 'series_completed' || type == 'series_completed') {
      debugPrint('⌚ [Wearable Action] ¡Serie completada desde el reloj!');
      final wearAction = SeriesCompletedWearAction.fromMap(message);
      _onSeriesCompletedCallback?.call(wearAction);
    } else if (action == 'request_qr' || type == 'request_qr') {
      debugPrint('⌚ [Wearable Action] Reloj solicitó nuevo código QR de acceso.');
      _onQrRequestedCallback?.call();
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    debugPrint('⌚ [Wearable MethodChannel] Método nativo convocado: ${call.method}');
    switch (call.method) {
      case 'onSeriesCompleted':
        if (call.arguments is Map) {
          final map = Map<String, dynamic>.from(call.arguments as Map);
          _processIncomingMessage(map);
        }
        return true;
      case 'onRequestQrToken':
        _onQrRequestedCallback?.call();
        return true;
      default:
        throw PlatformException(code: 'UNIMPLEMENTED', message: 'Método no implementado por WearableService.');
    }
  }
}
