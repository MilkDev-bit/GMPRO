/// @file lib/core/services/notification_router.dart
/// @description Enrutamiento interno (Deep Linking) al tocar una notificación.
/// Desacoplado de la UI (R1): navega vía el navigatorKey global ya existente
/// (ToastService.navigatorKey), sin recibir BuildContext.
///
/// Convención de payload (FCM `data` o payload del local notification):
///   { "route": "workout" | "streak" | "payment" | "profile", "id": "<opcional>" }
/// El backend controla el enrutamiento poniendo esos campos en `data`.

import 'package:flutter/widgets.dart';

import 'toast_service.dart';

class NotificationRouter {
  NotificationRouter._();

  /// Registro de destinos: route → builder de pantalla. Se rellena en el
  /// arranque para no acoplar este archivo con las vistas concretas.
  static final Map<String, Widget Function(String? id)> _routes = {};

  /// Registra los destinos disponibles (llamar una vez en main, tras montar la app).
  static void register(Map<String, Widget Function(String? id)> routes) {
    _routes
      ..clear()
      ..addAll(routes);
  }

  /// Procesa el `data` de un mensaje/notificación y navega si corresponde.
  /// Tolerante: si falta la ruta o no está registrada, no hace nada (no crashea).
  static void handle(Map<String, dynamic>? data) {
    if (data == null) return;
    final route = data['route']?.toString();
    if (route == null || route.isEmpty) return;

    final builder = _routes[route];
    if (builder == null) return; // ruta desconocida → ignorar en silencio

    final navigator = ToastService.navigatorKey.currentState;
    if (navigator == null) return; // app aún sin árbol de navegación

    final id = data['id']?.toString();
    navigator.push(MaterialPageRoute(builder: (_) => builder(id)));
  }
}
