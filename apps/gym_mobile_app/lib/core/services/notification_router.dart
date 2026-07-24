/// @file lib/core/services/notification_router.dart
/// @description Enrutamiento interno (Deep Linking de Push) DELEGADO a go_router.
/// Unifica Universal/App Links y notificaciones FCM bajo el mismo árbol de rutas.
///
/// Diseño (R2 del prompt: invocación global segura):
///   Las notificaciones pueden llegar en segundo plano o con la app terminada,
///   FUERA del árbol de widgets. Por eso NO dependemos de un BuildContext:
///   guardamos una referencia al `ProviderContainer` de Riverpod y obtenemos el
///   `GoRouter` para llamar a `router.go(location)`, que NO requiere context.
///   Si el router aún no está listo (arranque desde estado terminado), se guarda
///   el destino pendiente y se aplica en `attach()`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_router.dart';
import 'toast_service.dart';

class NotificationRouter {
  NotificationRouter._();

  static ProviderContainer? _container;

  /// Deep link recibido ANTES de que el contenedor/router estuvieran listos
  /// (típico en cold-start desde una notificación con la app terminada).
  static String? _pendingLocation;

  /// Inyecta el contenedor de Riverpod (llamar en main, antes de runApp).
  /// Aplica cualquier deep link que hubiera quedado pendiente.
  static void attach(ProviderContainer container) {
    _container = container;
    final pending = _pendingLocation;
    if (pending != null) {
      _pendingLocation = null;
      _navigate(pending);
    }
  }

  /// Punto de entrada: recibe el `data` de la notificación (FCM o local),
  /// lo traduce a una ruta de go_router y navega. Tolerante a fallos (R3).
  static void handle(Map<String, dynamic>? data) {
    final location = _resolveLocation(data);
    if (location == null) return; // ruta desconocida → ignorar sin crashear
    _navigate(location);
  }

  /// Mapeo DECLARATIVO payload → ubicación de go_router.
  ///   {"route":"workout"|"routine","id":"123"} → /routine/123
  ///   {"route":"payment"}                       → /stripe/return
  ///   {"route":"home"}                          → /
  static String? _resolveLocation(Map<String, dynamic>? data) {
    if (data == null) return null;
    final route = data['route']?.toString();
    final id = data['id']?.toString();

    switch (route) {
      case 'workout':
      case 'routine':
        // Falta el id requerido → fallback suave a Home (R3), no ruta rota.
        if (id == null || id.isEmpty) return '/';
        return '/routine/${Uri.encodeComponent(id)}';
      case 'payment':
        return '/stripe/return';
      case 'home':
        return '/';
      default:
        return null; // ruta desconocida → se ignora
    }
  }

  /// Navega vía GoRouter (sin BuildContext). Con doble red de seguridad.
  static void _navigate(String location) {
    final container = _container;
    if (container == null) {
      // Aún no hay router: guardamos el destino para aplicarlo en attach().
      _pendingLocation = location;
      return;
    }
    try {
      // GoRouter.go(location) NO necesita context → seguro fuera del árbol.
      container.read(goRouterProvider).go(location);
    } catch (_) {
      // Último recurso: usar el context del navigatorKey global si existe.
      try {
        ToastService.navigatorKey.currentContext?.go(location);
      } catch (_) {
        // Nunca romper la experiencia por un deep link (R3).
      }
    }
  }
}
