/// @file lib/core/services/notification_service.dart
/// @description Capa de dominio y datos para notificaciones nativas Enriquecidas (Rich Notifications)
/// con soporte de Big Picture, Attachments en iOS, AI Coach Avatar, Botones en segundo plano y Sonido Neón.

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../network/api_client.dart';
import 'toast_service.dart';

// ── MODELOS AUXILIARES PARA ACCIONES Y CATEGORÍAS ────────────────────────────
class NotificationActionOption {
  final String id;
  final String title;
  final bool showsUserInterface;

  const NotificationActionOption({
    required this.id,
    required this.title,
    this.showsUserInterface = true,
  });
}

// ── HANDLER EN SEGUNDO PLANO (TOP-LEVEL / ISOLATE) ───────────────────────────
/// Handler que se ejecuta cuando el usuario presiona un botón de acción en una notificación
/// desde segundo plano sin necesidad de abrir la interfaz de usuario (ej. "+250ml de agua").
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) async {
  debugPrint('⚡ [Notification Background Action] Botón presionado: ${response.actionId} | Payload: ${response.payload}');

  if (response.actionId == 'add_water_250' || response.actionId == 'add_water_500') {
    final amount = response.actionId == 'add_water_250' ? 250 : 500;
    try {
      final dio = Dio();
      await dio.post(
        '${AppConfig.fitnessServiceBaseUrl}/nutrition/water/log',
        data: {
          'amount_ml': amount,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'action_source': 'background_notification',
        },
      );
      debugPrint('💧 [Background Notification] +${amount}ml registrados en Supabase exitosamente.');
    } catch (e) {
      debugPrint('❌ [Background Notification] Error registrando agua: $e');
    }
  }
}

// ── 1. CONTRATO ABSTRACTO DE SERVICIO (Domain/Contract) ──────────────────────
abstract class NotificationService {
  /// Inicializa los canales nativos con categorías interactivas y callbacks.
  Future<void> initialize();

  /// Solicita interactivamente los permisos del sistema (iOS y Android 13+).
  Future<bool> requestPermissions();

  /// Captura el Token único de registro push (FCM / APNs) del dispositivo.
  Future<String?> getDeviceToken();

  /// Envía y asocia el FCM Token al backend en Railway / Supabase.
  Future<void> registerDeviceTokenWithBackend({
    required String userId,
    required ApiClient apiClient,
  });

  /// Muestra una notificación local estándar de alta prioridad con color de marca (#00F0FF).
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Muestra una Notificación Enriquecida (Rich Notification) con multimedia, avatar e interactividad.
  /// - [imageUrl]: Imagen principal para BigPictureStyle (Android) o UNNotificationAttachment (iOS).
  /// - [largeIconUrl] o [isAiCoach]: Muestra el Large Icon circular del AI Coach como si fuera persona real.
  /// - [actions]: Botones nativos interactivos rápidos debajo del texto (+250ml, Pagar ahora, etc.).
  Future<void> showRichNotification({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    String? largeIconUrl,
    bool isAiCoach = false,
    String? categoryId,
    List<NotificationActionOption>? actions,
    String? payload,
  });

  /// Programa una notificación local en una fecha y hora específica.
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
  NotificationServiceImpl._();
  static final NotificationServiceImpl instance = NotificationServiceImpl._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final Dio _dio = Dio();

  /// Canal nativo de alta importancia para Android con sonido deportivo neón y color de marca (#00F0FF).
  /// [AUDIO NATIVO]:
  /// - Android: Arrastrar 'gympro_neon_sound.wav' (o .mp3) a `/android/app/src/main/res/raw/gympro_neon_sound.wav`
  /// - Apple (iOS): Arrastrar 'gympro_neon_sound.wav' a `/ios/Runner/gympro_neon_sound.wav` y registrar en Xcode.
  static const AndroidNotificationChannel _highImportanceChannel = AndroidNotificationChannel(
    'gympro_high_importance_channel',
    'Alerta y Cobros GymPro',
    description: 'Canal de alta prioridad para notificaciones biométricas y de membresías en tiempo real.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('gympro_neon_sound'),
    enableVibration: true,
  );

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // A. Definición de Categorías Interactivas de Apple (DarwinNotificationCategory)
      final darwinCategories = <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          'hydration_category',
          actions: [
            DarwinNotificationAction.plain('add_water_250', '+250ml', options: {
              DarwinNotificationActionOption.foreground,
            }),
            DarwinNotificationAction.plain('add_water_500', '+500ml', options: {
              DarwinNotificationActionOption.foreground,
            }),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
        DarwinNotificationCategory(
          'payment_category',
          actions: [
            DarwinNotificationAction.plain('pay_stripe', 'Pagar ahora con Stripe', options: {
              DarwinNotificationActionOption.foreground,
            }),
          ],
        ),
      ];

      // B. Ajustes de Inicialización
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: darwinCategories,
      );

      final initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onDidReceiveBackgroundNotificationResponse,
      );

      // C. Crear canal nativo en Android con su sonido personalizado
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_highImportanceChannel);
      }

      // D. Configuración de presentación de Firebase Messaging en primer plano
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // E. Escuchar mensajes push entrantes en Foreground y redirecciones de toque en Background
      FirebaseMessaging.onMessage.listen(_onForegroundMessageReceived);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      _isInitialized = true;
      debugPrint('🔔 [NotificationService] Inicializado con Notificaciones Enriquecidas en ${Platform.operatingSystem}');
    } catch (e, stack) {
      debugPrint('❌ [NotificationService] Error en inicialización: $e\n$stack');
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      bool granted = false;

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (Platform.isAndroid) {
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final androidGranted = await androidImplementation?.requestNotificationsPermission();
        if (androidGranted != null) {
          granted = granted && androidGranted;
        }
      }

      debugPrint('🛡️ [NotificationService] Permisos otorgados: $granted');
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
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('⚠️ [NotificationService] APNs token no disponible aún en iOS.');
        }
      }
      final fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('📲 [NotificationService] FCM Token capturado: $fcmToken');
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

      final response = await apiClient.post(
        '${AppConfig.authServiceBaseUrl}/users/device-token',
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('🔒 [NotificationService] FCM Token asociado al usuario $userId en Supabase.');
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
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
    } catch (e) {
      debugPrint('⚠️ [NotificationService] Error al registrar FCM Token: $e');
    }
  }

  @override
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await showRichNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Construye la ruta de un adjunto GARANTIZANDO que quede dentro de [baseDir].
  ///
  /// Mitiga path traversal (CWE-22) en tres capas:
  ///   1. Sanea [rawName] a un ÚNICO componente de archivo: solo `[A-Za-z0-9_-]`.
  ///      Esto neutraliza separadores (`/`, `\`), secuencias `..` y rutas
  ///      absolutas (p.ej. `/etc/passwd` o `../../Library/...`) convirtiéndolos
  ///      en `_`.
  ///   2. Normaliza y canonicaliza tanto la base como el candidato (resuelve
  ///      `.`, `..` y separadores redundantes a una ruta absoluta real).
  ///   3. Verifica con [p.isWithin] que el candidato sea descendiente de la base;
  ///      si algo se escapó, lanza y aborta el guardado (falla de forma segura).
  static String _resolveSafeAttachmentPath(String baseDir, String rawName) {
    final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (safeName.isEmpty) {
      throw ArgumentError('Nombre de adjunto inválido');
    }
    final candidate = p.normalize(p.join(baseDir, '$safeName.jpg'));
    final canonicalBase = p.canonicalize(baseDir);
    final canonicalCandidate = p.canonicalize(candidate);
    if (!p.isWithin(canonicalBase, canonicalCandidate)) {
      throw ArgumentError(
        'Ruta de adjunto fuera del directorio temporal esperado: $rawName',
      );
    }
    return candidate;
  }

  @override
  Future<void> showRichNotification({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    String? largeIconUrl,
    bool isAiCoach = false,
    String? categoryId,
    List<NotificationActionOption>? actions,
    String? payload,
  }) async {
    try {
      // 1. Descarga y resolución asíncrona de la imagen principal (Attachment / BigPictureStyle)
      Uint8List? bigPictureBytes;
      String? localAttachmentPath;

      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final response = await _dio.get<List<int>>(
            imageUrl,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)),
          );
          if (response.data != null) {
            bigPictureBytes = Uint8List.fromList(response.data!);
            // En Apple (iOS/macOS) requerimos el archivo guardado localmente para UNNotificationAttachment
            if (Platform.isIOS || Platform.isMacOS) {
              final tempDir = await getTemporaryDirectory();
              // Endurecimiento anti path traversal (CWE-22): construimos la ruta
              // desde un componente saneado y verificamos por canonicalización que
              // el resultado quede DENTRO de tempDir antes de escribir el archivo.
              final safePath =
                  _resolveSafeAttachmentPath(tempDir.path, 'notif_attachment_$id');
              final file = File(safePath);
              await file.writeAsBytes(bigPictureBytes);
              localAttachmentPath = file.path;
            }
          }
        } catch (imgError) {
          debugPrint('⚠️ [NotificationService] Falló la descarga de imagen ($imageUrl): $imgError. Usando fallback de texto.');
        }
      }

      // 2. Resolución del Large Icon (Avatar de AI Coach o Ícono personalizado)
      Uint8List? largeIconBytes;
      if (largeIconUrl != null && largeIconUrl.isNotEmpty) {
        try {
          final response = await _dio.get<List<int>>(
            largeIconUrl,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 6)),
          );
          if (response.data != null) {
            largeIconBytes = Uint8List.fromList(response.data!);
          }
        } catch (e) {
          debugPrint('⚠️ [NotificationService] No se pudo descargar Large Icon: $e');
        }
      } else if (isAiCoach && bigPictureBytes != null) {
        // Si es AI Coach y no hay URL secundaria de ícono, reusamos el bigPicture o ícono por defecto
        largeIconBytes = bigPictureBytes;
      }

      // 3. Mapeo de Botones Inline Nativos para Android
      final androidActions = actions?.map((action) {
        return AndroidNotificationAction(
          action.id,
          action.title,
          showsUserInterface: action.showsUserInterface,
        );
      }).toList();

      // 4. Configuración del Estilo BigPicture para Android
      BigPictureStyleInformation? bigPictureStyleInformation;
      if (bigPictureBytes != null) {
        bigPictureStyleInformation = BigPictureStyleInformation(
          ByteArrayAndroidBitmap(bigPictureBytes),
          largeIcon: largeIconBytes != null ? ByteArrayAndroidBitmap(largeIconBytes) : null,
          contentTitle: title,
          summaryText: body,
        );
      }

      // 5. Resolución explícita del Large Icon en Android
      AndroidBitmap<Object>? resolvedLargeIcon;
      if (largeIconBytes != null) {
        resolvedLargeIcon = ByteArrayAndroidBitmap(largeIconBytes);
      } else if (isAiCoach) {
        resolvedLargeIcon = const DrawableResourceAndroidBitmap('@mipmap/ic_launcher');
      }

      // 6. Construcción de Detalles de Notificación en Android (#00F0FF Cyan Neón)
      final androidDetails = AndroidNotificationDetails(
        _highImportanceChannel.id,
        _highImportanceChannel.name,
        channelDescription: _highImportanceChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        color: const Color(0xFF00F0FF), // Acento de cabecera en color de marca Cyan Neón
        icon: '@mipmap/ic_launcher',
        largeIcon: resolvedLargeIcon,
        styleInformation: bigPictureStyleInformation,
        actions: androidActions,
        sound: const RawResourceAndroidNotificationSound('gympro_neon_sound'),
      );

      // 6. Construcción de Detalles de Notificación en Apple (iOS / macOS)
      final darwinAttachments = localAttachmentPath != null
          ? [DarwinNotificationAttachment(localAttachmentPath)]
          : <DarwinNotificationAttachment>[];

      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'gympro_neon_sound.wav',
        attachments: darwinAttachments,
        categoryIdentifier: categoryId,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _localNotifications.show(id, title, body, notificationDetails, payload: payload);
      debugPrint('🎨 [NotificationService] Notificación Enriquecida mostrada: "$title" (AI Coach: $isAiCoach)');
    } catch (e, stack) {
      debugPrint('❌ [NotificationService] Error emitiendo Notificación Enriquecida: $e\n$stack');
      // Fallback a notificación de texto simple si falla algo con los bytes o canales multimedia
      const fallbackDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'gympro_high_importance_channel',
          'Alerta y Cobros GymPro',
          importance: Importance.max,
          priority: Priority.high,
          color: Color(0xFF00F0FF),
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _localNotifications.show(id, title, body, fallbackDetails, payload: payload);
    }
  }

  @override
  Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final delay = scheduledDate.difference(DateTime.now());
    if (delay.isNegative) {
      await showLocalNotification(id: id, title: title, body: body, payload: payload);
      return;
    }

    Future.delayed(delay, () async {
      await showLocalNotification(id: id, title: title, body: body, payload: payload);
    });
  }

  // ── CALLBACKS INTERNOS EN PRIMER PLANO ─────────────────────────────────────

  void _onForegroundMessageReceived(RemoteMessage message) {
    debugPrint('🔔 [Foreground Push] Recibido de Railway: ${message.notification?.title} | ${message.notification?.body}');

    final notification = message.notification;
    final title = notification?.title ?? 'GymPro Notificación';
    final body = notification?.body ?? '';
    final data = message.data;
    final type = data['tipo']?.toString().toLowerCase() ?? 'info';
    final imageUrl = data['imagen_url'] ?? data['image'] ?? notification?.android?.imageUrl ?? notification?.apple?.imageUrl;
    final largeIconUrl = data['large_icon_url'] ?? data['avatar_url'];
    final isAiCoach = type == 'ai_coach' || data['source'] == 'ai';

    // 1. Mostrar Toast interactivo estilo Dynamic Island en la interfaz visible
    if (type == 'pago_exitoso' || type == 'success') {
      ToastService.showSuccessToast(title: title, message: body);
    } else if (type == 'pago_fallido' || type == 'acceso_denegado' || type == 'error') {
      ToastService.showErrorToast(title: title, message: body);
    } else if (type == 'alerta' || type == 'vencimiento_proximo' || type == 'warning') {
      ToastService.showWarningToast(title: title, message: body);
    } else {
      ToastService.showInfoToast(title: title, message: body);
    }

    // 2. Si el mensaje solicita emitir en bandeja o es de alta prioridad/AI Coach/Hidratación
    if (data['emitir_bandeja'] == 'true' || imageUrl != null || isAiCoach || type == 'hidratacion') {
      List<NotificationActionOption>? inlineActions;
      String? categoryId;

      if (type == 'hidratacion' || data['action_type'] == 'water') {
        categoryId = 'hydration_category';
        inlineActions = const [
          NotificationActionOption(id: 'add_water_250', title: '+250ml', showsUserInterface: false),
          NotificationActionOption(id: 'add_water_500', title: '+500ml', showsUserInterface: false),
        ];
      } else if (type == 'pago_fallido' || data['action_type'] == 'payment') {
        categoryId = 'payment_category';
        inlineActions = const [
          NotificationActionOption(id: 'pay_stripe', title: 'Pagar ahora con Stripe', showsUserInterface: true),
        ];
      }

      showRichNotification(
        id: notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        imageUrl: imageUrl,
        largeIconUrl: largeIconUrl,
        isAiCoach: isAiCoach,
        categoryId: categoryId,
        actions: inlineActions,
        payload: data['route'],
      );
    }
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('👆 [Push Tapped] Usuario abrió la app desde push: ${message.data}');
    final route = message.data['route']?.toString();
    if (route != null && route.isNotEmpty) {
      final navigator = ToastService.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(route);
      }
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('👆 [Notification Response] Tocado: ${response.actionId} | Payload: ${response.payload}');
    if (response.actionId == 'add_water_250' || response.actionId == 'add_water_500') {
      // Si se presionó con la app en primer plano, también delegamos al log de agua
      onDidReceiveBackgroundNotificationResponse(response);
      ToastService.showSuccessToast(
        title: '¡Hidratación registrada!',
        message: response.actionId == 'add_water_250' ? '+250ml añadidos.' : '+500ml añadidos.',
      );
    } else if (response.actionId == 'pay_stripe' || (response.payload != null && response.payload!.isNotEmpty)) {
      final route = response.payload ?? '/subscription/checkout';
      final navigator = ToastService.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamed(route);
      }
    }
  }
}
