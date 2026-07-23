/// @file lib/core/network/api_client.dart
/// @description Cliente HTTP Dio configurado con timeouts, aislamiento (compute) e interceptores
/// avanzados de resiliencia: Autenticación, Reintentos (Exponential Backoff) y Caché Local Efímera.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../storage/local_cache_service.dart';
import '../storage/secure_storage_service.dart';
import 'auth_interceptor.dart';
import 'cache_interceptor.dart';
import 'retry_interceptor.dart';
import 'ssl_pinning_adapter.dart';

class ApiClient {
  late final Dio _dio;
  final SecureStorageService _storageService;
  final LocalCacheService _cacheService;

  ApiClient({
    SecureStorageService? storageService,
    LocalCacheService? cacheService,
  })  : _storageService = storageService ?? SecureStorageService(),
        _cacheService = cacheService ?? LocalCacheService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.authServiceBaseUrl,
        connectTimeout: AppConfig.connectionTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );

    // Certificate Pinning (SPKI): solo en plataformas nativas (dart:io). En web
    // no aplica ni existe IOHttpClientAdapter. El kill-switch/local se resuelve
    // dentro del adapter (AppConfig.isSSLPinningEnabled).
    if (!kIsWeb) {
      _dio.httpClientAdapter = SSLPinningAdapter.build();
    }

    // El orden de los interceptores es fundamental para la resiliencia:
    // 1. AuthInterceptor: Adjunta Bearer token y cabeceras de cliente
    _dio.interceptors.add(AuthInterceptor(_storageService));

    // 2. RetryInterceptor: Reintenta hasta 3 veces (1s, 2s, 4s) ante timeouts o 503/502/504
    _dio.interceptors.add(RetryInterceptor(dio: _dio, maxRetries: 3));

    // 3. CacheInterceptor: Persiste respuestas GET 200 y hace fallback automático si la red/reintentos fallan
    _dio.interceptors.add(CacheInterceptor(cacheService: _cacheService));
  }

  Dio get dio => _dio;
  LocalCacheService get cacheService => _cacheService;

  /// Petición POST estandarizada con soporte para opciones de resiliencia
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool noRetry = false,
  }) async {
    final effectiveOptions = options ?? Options();
    effectiveOptions.extra = {
      ...?effectiveOptions.extra,
      'no_retry': noRetry,
    };

    return await _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: effectiveOptions,
    );
  }

  /// Petición GET estandarizada con soporte para caché local efímero y reintentos
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool noCache = false,
    bool forceCache = false,
    bool noRetry = false,
  }) async {
    final effectiveOptions = options ?? Options();
    effectiveOptions.extra = {
      ...?effectiveOptions.extra,
      'no_cache': noCache,
      'force_cache': forceCache,
      'no_retry': noRetry,
    };

    return await _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: effectiveOptions,
    );
  }

  /// Petición PUT estandarizada
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Petición DELETE estandarizada
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return await _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Parsea cualquier payload JSON en un hilo secundario/Isolate usando compute()
  /// para evitar congelamientos (jank) en el hilo principal de la UI al deserializar.
  static Future<R> parseInBackground<T, R>(
    R Function(T) parser,
    T data,
  ) async {
    return compute(parser, data);
  }
}
