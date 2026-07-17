/// @file lib/core/network/cache_interceptor.dart
/// @description Interceptor de red que automatiza la estrategia de Caché Local Efímero.
/// Si una petición GET (ej. /api/v1/recommendations/diet o catálogos de ejercicios) falla por
/// falta de conexión o tras agotar los reintentos, intercepta el error y sirve el último
/// JSON exitoso almacenado en LocalCacheService sin interrumpir al usuario.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/local_cache_service.dart';

class CacheInterceptor extends Interceptor {
  final LocalCacheService cacheService;

  /// Endpoints que deben almacenarse y permitir fallback local
  final List<String> _cacheableEndpoints = const [
    '/recommendations/diet',
    '/recommendations/workout',
    '/exercise',
    '/exercises',
    '/catalog',
    '/nutrition/plan',
    '/workouts/plan',
  ];

  CacheInterceptor({required this.cacheService});

  /// Determina si una URL específica es elegible para caché local efímero
  bool _isCacheable(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return false;
    if (options.extra['no_cache'] == true) return false;
    if (options.extra['force_cache'] == true) return true;

    return _cacheableEndpoints.any((endpoint) => options.path.contains(endpoint));
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    // Si la respuesta fue exitosa y es cacheable, persistirla silenciosamente
    if (response.statusCode == 200 && _isCacheable(response.requestOptions)) {
      await cacheService.saveResponse(
        response.requestOptions.path,
        response.data,
        queryParameters: response.requestOptions.queryParameters,
      );
    }
    return super.onResponse(response, handler);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    // Solo activamos fallback local en peticiones GET cacheables ante problemas de conectividad o 500s
    if (_isCacheable(options) && _isOfflineOrServerDown(err)) {
      if (kDebugMode) {
        print('📡 [CacheInterceptor] Falló petición a ${options.path} tras reintentos. Verificando caché efímera local...');
      }

      final cachedData = await cacheService.getResponse(
        options.path,
        queryParameters: options.queryParameters,
      );

      if (cachedData != null) {
        if (kDebugMode) {
          print('🟢 [CacheInterceptor] Fallback local exitoso para ${options.path}. Sirviendo respuesta guardada.');
        }

        // Construir una respuesta HTTP sintética exitosa para que la UI/Repositorio continúe normalmente
        final syntheticResponse = Response(
          requestOptions: options,
          data: cachedData,
          statusCode: 200,
          statusMessage: 'OK (Ephemeral Local Cache Fallback)',
          headers: Headers.fromMap({
            'x-cache-fallback': ['true'],
            'content-type': ['application/json; charset=utf-8'],
          }),
        );

        return handler.resolve(syntheticResponse);
      } else if (kDebugMode) {
        print('⚠️ [CacheInterceptor] No hay datos en caché efímera para ${options.path}. Arrojando Failure al usuario.');
      }
    }

    return super.onError(err, handler);
  }

  bool _isOfflineOrServerDown(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = err.response?.statusCode ?? 0;
    return statusCode >= 500 && statusCode <= 599;
  }
}
