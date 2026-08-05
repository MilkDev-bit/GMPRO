/// @file lib/core/network/auth_interceptor.dart
/// @description Interceptor de Dio: adjunta el Bearer SOLO a hosts del backend
/// (anti token-leakage) y gestiona el ciclo de vida de la sesión con un
/// REFRESH TOKEN flow concurrente-seguro (single-flight + cola de reintentos).

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../storage/secure_storage_service.dart';

/// Marca en RequestOptions.extra para no reintentar la misma petición dos veces
/// (rompe cualquier bucle refresh ↔ 401).
const String _kRetriedFlag = '__auth_retried__';

class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;

  /// Callback opcional para forzar el redirect a login cuando la sesión expira
  /// de forma irrecuperable (el interceptor no tiene BuildContext).
  final void Function()? _onSessionExpired;

  AuthInterceptor(
    this._storageService, {
    void Function()? onSessionExpired,
    Dio? refreshClient,
  })  : _onSessionExpired = onSessionExpired,
        _injectedRefreshDio = refreshClient;

  /// Permite inyectar el Dio de refresh en tests. En producción es null y se
  /// crea el `_refreshDio` interno por defecto.
  final Dio? _injectedRefreshDio;

  /// Dio DEDICADO al /refresh y a los reintentos: en producción SIN
  /// interceptores, para no re-entrar en este mismo onError (bucle infinito).
  /// Punto #4 del requisito. En tests se inyecta uno con mock adapter.
  late final Dio _refreshDio = _injectedRefreshDio ??
      Dio(
        BaseOptions(
          baseUrl: AppConfig.authServiceBaseUrl,
          connectTimeout: AppConfig.connectionTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
        ),
      );

  /// Guard SINGLE-FLIGHT: si hay un refresh en curso, las demás peticiones 401
  /// esperan ESTE future en vez de disparar su propio /refresh (que el backend
  /// trataría como replay → revocaría la familia entera → logout masivo).
  Completer<bool>? _refreshCompleter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Candado anti token-leakage: el Bearer SOLO va a hosts del backend.
    final isBackend = AppConfig.isBackendHost(options.uri.host);
    // Endpoints PÚBLICOS (no llevan Bearer). Coincidencia EXACTA de ruta: con
    // `contains` antes, `/passkey/register-options` matcheaba "/register" y se
    // trataba como público → 401 al crear la passkey (que SÍ requiere JWT).
    final path = options.path.split('?').first;
    const publicPaths = <String>{
      '/register',
      '/login',
      '/oauth-login',
      '/verify-email',
      '/otp/verify',
      '/refresh',
      '/passkey/login-options',
      '/passkey/verify-login',
    };
    final isPublicEndpoint = publicPaths.contains(path);

    if (isBackend && !isPublicEndpoint) {
      final token = await _storageService.getAccessToken();
      // DIAGNÓSTICO passkey 401: ¿llega el Bearer a /passkey/register-options?
      debugPrint('🔐 [Auth] $path backend=$isBackend public=$isPublicEndpoint '
          'token=${token == null ? "NULL" : (token.isEmpty ? "EMPTY" : "len=${token.length}")}');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    options.headers['Accept'] = 'application/json';
    options.headers['X-Client-App'] = 'GymPro-Mobile/1.0.0';
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final status = err.response?.statusCode;

    final isRefreshCall = options.path.contains('/refresh');
    final isAuthEndpoint = options.path.contains('/login') ||
        options.path.contains('/oauth-login');
    final alreadyRetried = options.extra[_kRetriedFlag] == true;

    // Solo intervenimos ante 401 de NUESTRO backend, en peticiones que no sean
    // de auth/refresh y que aún no se hayan reintentado.
    final shouldTryRefresh = status == 401 &&
        AppConfig.isBackendHost(options.uri.host) &&
        !isRefreshCall &&
        !isAuthEndpoint &&
        !alreadyRetried;

    if (!shouldTryRefresh) {
      // Un 401 en /refresh o en una petición ya reintentada = sesión muerta.
      if (status == 401 && (isRefreshCall || alreadyRetried)) {
        await _forceLogout('401 irrecuperable en ${options.path}');
      }
      return handler.next(err);
    }

    // ── Refresh SINGLE-FLIGHT: uno solo; el resto de 401 concurrentes esperan ─
    final refreshed = await _refreshSingleFlight();

    if (!refreshed) {
      await _forceLogout('El refresh falló; se cierra la sesión');
      return handler.next(err);
    }

    // ── Reintento de la petición original con el nuevo token ─────────────────
    try {
      final newToken = await _storageService.getAccessToken();
      options.headers['Authorization'] = 'Bearer $newToken';
      options.extra[_kRetriedFlag] = true;
      final response = await _refreshDio.fetch(options); // sin interceptores
      return handler.resolve(response);
    } catch (_) {
      // Si el reintento vuelve a fallar, propagamos el error original.
      return handler.next(err);
    }
  }

  /// Devuelve el future del refresh en curso, o inicia uno nuevo si no hay.
  /// La comprobación-y-asignación del completer es ATÓMICA: no hay `await`
  /// entre leer `_refreshCompleter` y asignarlo, y Dart es de un solo hilo →
  /// dos 401 concurrentes nunca lanzan dos /refresh.
  Future<bool> _refreshSingleFlight() {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future; // ya hay refresh → esperarlo

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    _performRefresh().then((ok) {
      completer.complete(ok);
    }).catchError((Object _) {
      completer.complete(false);
    }).whenComplete(() {
      _refreshCompleter = null; // liberar para la próxima oleada
    });

    return completer.future;
  }

  /// Llamada REAL a /refresh con Dio limpio. El refresh token viaja como Cookie
  /// (el backend lo lee de `req.cookies.refreshToken`) y los nuevos tokens
  /// llegan en el body JSON (`data.accessToken` / `data.refreshToken`).
  Future<bool> _performRefresh() async {
    final refreshToken = await _storageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final resp = await _refreshDio.post(
        '/refresh',
        options: Options(headers: {'Cookie': 'refreshToken=$refreshToken'}),
      );

      final data = (resp.data is Map) ? resp.data['data'] : null;
      final newAccess = data?['accessToken'] as String?;
      final newRefresh = data?['refreshToken'] as String?;
      if (newAccess == null || newAccess.isEmpty ||
          newRefresh == null || newRefresh.isEmpty) {
        return false;
      }

      await _storageService.updateTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      AppLogger.d('Sesión renovada correctamente', tag: 'AuthInterceptor');
      return true;
    } on DioException catch (e) {
      // 401/403 → refresh token inválido/revocado (o reuse detectado en backend).
      AppLogger.w(
        'Refresh rechazado (${e.response?.statusCode ?? e.type.name})',
        tag: 'AuthInterceptor',
      );
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Limpieza atómica de la sesión + señal de redirect a login (fail-safe).
  Future<void> _forceLogout(String reason) async {
    AppLogger.d('Logout forzado: $reason', tag: 'AuthInterceptor');
    await _storageService.clearAuth();
    _onSessionExpired?.call();
  }
}
