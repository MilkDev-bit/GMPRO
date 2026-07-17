/// @file lib/core/services/notification_service.dart
/// @description Capa de dominio y datos para el manejo de notificaciones nativas locales y push (FCM/APNs).

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import 'toast_service.dart';

// ── 1. CONTRATO ABSTRACTO DE SERVICIO (Domain/Contract) ──────────────────────
abstract class NotificationService {
  /// Inicializa los canales nativos en Android y Apple e inyecta oyentes de primer plano.
  Future<void> initialize();

  /// Solicita interactivamente los permisos del sistema (iOS y Android 13+ Tiramisu).
  Future<bool> requestPermissions();

  /// Captura el Token único de registro push (FCM / APNs token) del dispositivo físico.
  Future<String?> getDeviceToken();

  /// Envía y asocia el FCM Token de este dispositivo al `usuario_id` en el backend (Railway/Supabase).
  Future<void> registerDeviceTokenWithBackend({
    required String userId,
    required ApiClient apiClient,
  });

  /// Muestra una notificación local inmediata en la bandeja del sistema nativo.
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Programa una notificación local en una fecha y hora específica (Ej. Recordatorio de rutina).
  Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  });
}

// ── 2. IMPLEMENTACIÓN CONCRETA (Data/Implementation) ─────────────────────────
class NotificationServiceImpl implements NotificationService {
  NotificationServiceImpl._(); // Singleton
  static final NotificationServiceImpl instance = NotificationServiceImpl._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Canal nativo de alta importancia para Android (Cobros, Alertas y Acceso QR).
  static const AndroidNotificationChannel _highImportanceChannel = AndroidNotificationChannel(
    'gympro_high_importance_channel',
    'Alerta y Cobros GymPro',
    description: 'Canal de alta prioridad para notificaciones biométricas y de membresías en tiempo real.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // A. Configuración inicial de íconos y callbacks nativos
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlert: false, // Pediremos permisos de manera explícita luego con requestPermissions()
        requestBadge: false,
        requestSound: false,
      );

      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // B. Crear canal nativo en Android
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_highImportanceChannel);
      }

      // C. Configurar presentación en primer plano para iOS
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // D. Escuchar mensajes push mientras la app está abierta en primer plano (Foreground)
      FirebaseMessaging.onMessage.listen(_onForegroundMessageReceived);

      // E. Escuchar cuando el usuario toca la notificación desde segundo plano y abre la app
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      _isInitialized = true;
      debugPrint('🔔 [NotificationService] Inicializado exitosamente en ${Platform.operatingSystem}');
    } catch (e, stack) {
      debugPrint('❌ [NotificationService] Error en inicialización: $e\n$stack');
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      bool granted = false;

      // 1. Permiso en Firebase Messaging / iOS UNUserNotificationCenter
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // 2. Permiso explícito para Android 13+ (POST_NOTIFICATIONS)
      if (Platform.isAndroid) {
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final androidGranted = await androidImplementation?.requestNotificationsPermission();
        if (androidGranted != null) {
          granted = granted && androidGranted;
        }
      }

      debugPrint('🛡️ [NotificationService] Estado de permisos otorgado: $granted');
      return granted;
    } catch (e) {
      debugPrint('❌ [NotificationService] Error solicitando permisos: $e');
      return false;
    }
  }

  @override
  Future<String?> getDeviceToken() async {
    try {
      if (Platform.isIOS) {
        // En iOS, necesitamos asegurar que el token APNs esté disponible primero
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('⚠️ [NotificationService] APNs token no disponible aún en iOS.');
        }
      }

      final fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('📲 [NotificationService] FCM Device Token capturado: $fcmToken');
      return fcmToken;
    } catch (e) {
      debugPrint('❌ [NotificationService] Error obteniendo FCM token: $e');
      return null;
    }
  }

  @override
  Future<void> registerDeviceTokenWithBackend({
    required String userId,
    required ApiClient apiClient,
  }) async {
    try {
      final token = await getDeviceToken();
      if (token == null || token.isEmpty) return;

      final payload = {
        'usuario_id': userId,
        'fcm_token': token,
        'plataforma': Platform.operatingSystem,
        'dispositivo_info': Platform.isAndroid ? 'Android Device' : 'Apple iOS Device',
        'registrado_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Enviamos el token al endpoint de autenticación / dispositivos del microservicio en Railway
      final response = await apiClient.post(
        '${AppConfig.authServiceBaseUrl}/users/device-token',
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('🔒 [NotificationService] FCM Token asociado exitosamente al usuario $userId en Supabase/Railway.');
      }

      // Escuchar si el token se renueva en el futuro para actualizarlo automáticamente
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 [NotificationService] FCM Token rotado por Firebase. Enviando al backend...');
        await apiClient.post(
          '${AppConfig.authServiceBaseUrl}/users/device-token',
          data: {
            'usuario_id': userId,
            'fcm_token': newToken,
            'plataforma': Platform.operatingSystem,
            'actualizado_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      });
    } on DioException catch (e) {
      debugPrint('⚠️ [NotificationService] Error HTTP al registrar FCM Token (no crítico): ${e.message}');
    } catch (e) {
      debugPrint('❌ [NotificationService] Error general registrando FCM Token: $e');
    }
  }

  @override
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'gympro_high_importance_channel',
      'Alerta y Cobros GymPro',
      channelDescription: 'Canal de alta prioridad para notificaciones biométricas y de membresías en tiempo real.',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF9D00FF), // Neon Purple
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localNotifications.show(id, title, body, notificationDetails, payload: payload);
  }

  @override
  Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    // Para programaciones avanzadas, se puede usar zonedSchedule de flutter_local_notifications
    // Aquí implementamos el dispatch seguro:
    final delay = scheduledDate.difference(DateTime.now());
    if (delay.isNegative) {
      await showLocalNotification(id: id, title: title, body: body, payload: payload);
      return;
    }

    Future.delayed(delay, () async {
      await showLocalNotification(id: id, title: title, body: body, payload: payload);
    });
  }

  // ── Callbacks Internos ─────────────────────────────────────────────────────

  /// Manejo de notificación recibida con la aplicación en PRIMER PLANO.
  void _onForegroundMessageReceived(RemoteMessage message) {
    debugPrint('🔔 [Foreground Push] Recibido de Railway: ${message.notification?.title} | ${message.notification?.body}');

    final notification = message.notification;
    final title = notification?.title ?? 'GymPro Notificación';
    final body = notification?.body ?? '';
    final type = message.data['tipo']?.toString().toLowerCase() ?? 'info';

    // A. Mostrar Toast moderno estilo Dynamic Island / iOS en pantalla inmediatamente
    if (type == 'pago_exitoso' || type == 'success') {
      ToastService.showSuccessToast(title: title, message: body);
    } else if (type == 'pago_fallido' || type == 'acceso_denegado' || type == 'error') {
      ToastService.showErrorToast(title: title, message: body);
    } else if (type == 'alerta' || type == 'vencimiento_proximo' || type == 'warning') {
      ToastService.showWarningToast(title: title, message: body);
    } else {
      ToastService.showInfoToast(title: title, message: body);
    }

    // B. Opcional: También emitir una notificación local en la bandeja si el usuario está en otra pestaña
    if (message.data['emitir_bandeja'] == 'true' && notification != null) {
      showLocalNotification(
        id: notification.hashCode,
        title: title,
        body: body,
        payload: message.data['route'],
      );
    }
  }

  /// Manejo cuando el usuario toca una notificación en la bandeja del sistema y entra a la app.
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('👆 [Push Tapped] Usuario abrió la app desde push notification: ${message.data}');
    final route = message.data['route']?.toString();
    if (route != null && route.isNotEmpty) {
      // Redirigir usando el navigatorKey de ToastService si está disponible
      final navigator = ToastService.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(route);
      }
    }
  }

  /// Manejo cuando el usuario toca una notificación local generada por [FlutterLocalNotificationsPlugin].
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('👆 [Local Notification Tapped] Payload: ${response.payload}');
    final route = response.payload;
    if (route != null && route.isNotEmpty) {
      final navigator = ToastService.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(route);
      }
    }
  }
}
