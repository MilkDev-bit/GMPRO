/// @file lib/core/services/firebase_background_handler.dart
/// @description Handler en segundo plano para procesar notificaciones remotas (FCM) de forma segura.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Punto de entrada aislado para procesar notificaciones de Firebase Messaging en segundo plano (Background/Terminated).
///
/// ES CRÍTICO mantener esta función independiente del árbol de widgets o providers de UI para evitar
/// fugas de memoria o desbordamientos del sistema operativo en Android/iOS.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Inicializar Firebase en el aislamiento secundario si no ha sido inicializado
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    debugPrint('🌙 [Firebase Background Handler] Mensaje recibido ID: ${message.messageId}');
    debugPrint('📦 [Background Payload] Título: ${message.notification?.title} | Data: ${message.data}');

    // En este aislamiento no debemos abrir diálogos ni manipular Riverpod o Flutter UI.
    // El sistema operativo (Android NotificationManager / iOS APNs) mostrará automáticamente
    // la alerta en la bandeja del sistema si el payload incluye el objeto "notification".
    //
    // Si el mensaje es tipo "data-only" (silent push), aquí podemos actualizar datos locales en
    // SQLite/SharedPreferences o programar una alarma local con flutter_local_notifications si es requerido.
  } catch (e, stack) {
    debugPrint('❌ [Firebase Background Error] Error procesando notificación en segundo plano: $e\n$stack');
  }
}
