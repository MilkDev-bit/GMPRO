/// @file lib/core/logging/app_logger.dart
/// @description Logger centralizado del cliente con REDACCIÓN de secretos y
/// silenciado en producción (CWE-532 móvil).
///
/// Reglas:
///   • `d`/`i` (debug/info): SOLO se emiten en modo debug (`kDebugMode`). En
///     release son no-op → nada de ruido ni fuga a Logcat/Consola.
///   • `w`/`e` (warn/error): se emiten siempre vía `dart:developer.log` para
///     diagnóstico, PERO redactados. En release, conéctalos a un crash reporter
///     (Crashlytics/Sentry); nunca imprimen secretos en claro.
///   • Toda salida pasa por `_redact`, que enmascara JWT, claves Stripe/Supabase
///     y `Bearer …` aunque el llamador olvide filtrar.

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static final List<RegExp> _secretPatterns = <RegExp>[
    RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'), // JWT
    RegExp(r'[rs]k_(live|test)_[A-Za-z0-9]{8,}'),                          // Stripe secret/restricted
    RegExp(r'whsec_[A-Za-z0-9]{8,}'),                                      // Stripe webhook secret
    RegExp(r'sb_secret_[A-Za-z0-9]{8,}'),                                  // Supabase secret key
    RegExp(r'Bearer\s+[A-Za-z0-9._-]{8,}', caseSensitive: false),          // Bearer <token>
  ];

  static String _redact(Object? message) {
    var s = message?.toString() ?? '';
    for (final re in _secretPatterns) {
      s = s.replaceAll(re, '[REDACTED]');
    }
    return s;
  }

  /// Debug: visible solo en desarrollo.
  static void d(Object? message, {String tag = 'App'}) {
    if (kDebugMode) {
      developer.log(_redact(message), name: tag, level: 500);
    }
  }

  /// Info: alias de debug (visible solo en desarrollo).
  static void i(Object? message, {String tag = 'App'}) => d(message, tag: tag);

  /// Warning: se emite también en release, redactado.
  static void w(Object? message, {String tag = 'App'}) {
    developer.log(_redact(message), name: tag, level: 900);
  }

  /// Error: se emite también en release, redactado. Ideal para enganchar a un
  /// crash reporter (el `error`/`stackTrace` no debe llevar secretos).
  static void e(Object? message,
      {Object? error, StackTrace? stackTrace, String tag = 'App'}) {
    developer.log(
      _redact(message),
      name: tag,
      level: 1000,
      error: error != null ? _redact(error) : null,
      stackTrace: stackTrace,
    );
  }
}
