/// @file lib/core/network/auth_interceptor.dart
/// @description Interceptor de Dio que adjunta el Bearer Token desde SecureStorage a las peticiones salientes.

import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;

  AuthInterceptor(this._storageService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Si no es una ruta pública o de autenticación externa, adjuntar JWT
    if (!options.path.contains('/login') &&
        !options.path.contains('/register') &&
        !options.path.contains('/oauth-login')) {
      final token = await _storageService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    options.headers['Accept'] = 'application/json';
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Si recibimos 401 Unauthorized en una llamada autenticada, limpiar storage
    if (err.response?.statusCode == 401 && !err.requestOptions.path.contains('/login')) {
      await _storageService.clearAuth();
    }
    return handler.next(err);
  }
}
