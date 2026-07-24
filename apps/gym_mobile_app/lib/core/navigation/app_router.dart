/// @file lib/core/navigation/app_router.dart
/// @description Configuración central de GoRouter, incluyendo la intercepción de
/// Universal Links (iOS) / App Links (Android).
///
/// ¿Cómo intercepta GoRouter los deep links "bajo el capó"?
///   MaterialApp.router delega en el `Router` de Flutter, que usa un
///   `RouteInformationProvider`. GoRouter instala su propio
///   `GoRouteInformationProvider` (envuelve el `PlatformRouteInformationProvider`
///   de Flutter). Ese provider de plataforma recibe del engine (vía el canal
///   `flutter/navigation`) las URLs que el SO entrega cuando el usuario abre un
///   Universal/App Link. GoRouter parsea esa URI con su `RouteInformationParser`
///   y la resuelve contra la tabla `routes` — SIN que tengamos que escuchar un
///   stream manual (uni_links/app_links). Solo definimos las rutas aquí.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/toast_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/home/presentation/screens/home_dashboard_screen.dart';
import 'app_shell.dart';
import 'payment_return_screen.dart';
import 'routine_detail_screen.dart';

/// Puente Riverpod → GoRouter: notifica al router cada vez que cambia el estado
/// de auth, para que `redirect` se re-evalúe (login/logout en caliente).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

/// Provider del router (se crea UNA vez; Riverpod lo cachea).
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    // Reutiliza el navigatorKey global → ToastService/RASP/NotificationRouter
    // siguen funcionando sin cambios.
    navigatorKey: ToastService.navigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    // ── Auth gating (sin tocar los push; se resuelve por redirect) ───────────
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      // Mientras se resuelve la sesión inicial no rebotamos (evita flash de login).
      if (auth.status == AuthStatus.initial || auth.status == AuthStatus.loading) {
        return null;
      }
      final loggedIn = auth.isAuthenticated;
      final loggingIn = loc == '/login';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/';
      return null; // sin redirección
    },

    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AppShell(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // ── Ruta 1: retorno de Stripe (query parameters) ───────────────────────
      // Universal/App Link ejemplo:
      //   https://app.gympro.com/stripe/return?payment_intent_client_secret=pi_..&redirect_status=succeeded
      GoRoute(
        path: '/stripe/return',
        builder: (context, state) {
          // Query params → se leen de state.uri.queryParameters (go_router 14.x).
          final q = state.uri.queryParameters;
          return PaymentReturnScreen(
            clientSecret: q['payment_intent_client_secret'],
            // Stripe usa 'redirect_status'; aceptamos también 'status' por robustez.
            status: q['redirect_status'] ?? q['status'],
          );
        },
      ),

      // ── Ruta 2: rutina compartida (path parameter :id) ─────────────────────
      // Ejemplo: https://app.gympro.com/routine/abc-123
      GoRoute(
        path: '/routine/:id',
        builder: (context, state) {
          // Path param → state.pathParameters. Si falta, cae al errorBuilder.
          final id = state.pathParameters['id'];
          if (id == null || id.isEmpty) {
            return const HomeDashboardScreen(); // fallback defensivo
          }
          return RoutineDetailScreen(routineId: id);
        },
      ),
    ],

    // ── Ruta 4: fallback suave (deep link roto/inexistente) ──────────────────
    // Nada de pantalla roja: mostramos Home y redirigimos a '/' en el próximo
    // frame para dejar la URL limpia.
    errorBuilder: (context, state) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const HomeDashboardScreen();
    },
  );
});
