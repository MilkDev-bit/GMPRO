/// @file lib/core/network/retry_interceptor.dart
/// @description Interceptor de red que implementa un mecanismo inteligente de reintentos
/// con Exponential Backoff (1s, 2s, 4s) ante fallos transitorios (503 Service Unavailable,
/// 502 Bad Gateway, 504 Gateway Timeout y timeouts de conexión).

import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  // OJO: 429 (Too Many Requests) NO se reintenta. Reintentarlo multiplica las
  // peticiones (cada intento = 1 + N reintentos) y MANTIENE agotado el rate
  // limit. Ante 429 el cliente debe parar y respetar el Retry-After.
  final List<int> _retryStatuses = const [500, 502, 503, 504, 408];

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
  });

  /// Evalúa si el error recibido es candidato a reintento automático
  bool _shouldRetry(DioException err) {
    // 1. Verificar si la petición explícitamente prohíbe reintentos
    if (err.requestOptions.extra['no_retry'] == true) {
      return false;
    }

    // 2. Errores de tiempo de espera y conexión a nivel de socket
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    // 3. Códigos HTTP de indisponibilidad temporal del servidor (ej. 503 Service Unavailable)
    if (err.response != null && _retryStatuses.contains(err.response?.statusCode)) {
      return true;
    }

    return false;
  }

  /// Calcula el retraso con Exponential Backoff y un pequeño Jitter para evitar tormentas
  Duration _getBackoffDelay(int attempt) {
    // Fórmulas exponenciales: 2^(attempt-1) * 1000 ms => 1s, 2s, 4s...
    final baseMillis = (math.pow(2, attempt - 1) * 1000).toInt();
    // Añadir aleatoriedad entre 0ms y 250ms (Jitter) para descongestionar el servidor
    final jitterMillis = math.Random().nextInt(250);
    return Duration(milliseconds: baseMillis + jitterMillis);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final requestOptions = err.requestOptions;
    final currentAttempt = (requestOptions.extra['retry_attempt'] as int? ?? 0);

    if (_shouldRetry(err) && currentAttempt < maxRetries) {
      final nextAttempt = currentAttempt + 1;
      final delay = _getBackoffDelay(nextAttempt);

      requestOptions.extra['retry_attempt'] = nextAttempt;

      if (kDebugMode) {
        final reason = err.response != null
            ? 'HTTP ${err.response?.statusCode}'
            : err.type.name;
        print(
          '⏳ [RetryInterceptor] Reintento $nextAttempt/$maxRetries tras fallar ($reason) en ${requestOptions.path}. Espaciando ${delay.inMilliseconds}ms...',
        );
      }

      await Future.delayed(delay);

      try {
        // Realizar nuevamente la petición espaciada con la misma instancia Dio
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryError) {
        // Si el reintento vuelve a lanzar una excepción Dio, dejamos que siga el ciclo onError
        return super.onError(retryError, handler);
      } catch (unknownError) {
        return super.onError(err, handler);
      }
    }

    // Si no se debe reintentar o se agotaron los intentos (3/3), continuar con el error
    if (currentAttempt >= maxRetries && kDebugMode) {
      print('❌ [RetryInterceptor] Se agotaron los $maxRetries reintentos para ${requestOptions.path}. Arrojando fallo definitivo.');
    }

    return super.onError(err, handler);
  }
}
