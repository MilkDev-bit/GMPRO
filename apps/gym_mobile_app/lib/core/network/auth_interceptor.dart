/// @file lib/core/network/auth_interceptor.dart
/// @description Interceptor de Dio que adjunta el Bearer Token desde SecureStorage a las peticiones salientes
/// y maneja la expiración de sesiones (401 Unauthorized) con resiliencia y limpieza atómica.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;

  AuthInterceptor(this._storageService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. Omitir adjuntar JWT en endpoints públicos u OAuth nativos
    final isPublicEndpoint = options.path.contains('/login') ||
        options.path.contains('/register') ||
        options.path.contains('/oauth-login') ||
        options.path.contains('/verify-email');

    if (!isPublicEndpoint) {
      final token = await _storageService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    // 2. Cabeceras estándar de identificación del cliente y formato
    options.headers['Accept'] = 'application/json';
    options.headers['X-Client-App'] = 'GymPro-Mobile/1.0.0';
    options.headers['X-Device-Platform'] = defaultTargetPlatform.name;

    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final path = err.requestOptions.path;

    // Si recibimos 401 Unauthorized en una llamada autenticada y no es un login/oauth falido
    if (statusCode == 401 && !path.contains('/login') && !path.contains('/oauth-login')) {
      if (kDebugMode) {
        print('🔒 [AuthInterceptor] Sesión expirada o token revocado (401 en $path). Limpiando SecureStorage...');
      }
      await _storageService.clearAuth();
    }

    return handler.next(err);
  }
}
