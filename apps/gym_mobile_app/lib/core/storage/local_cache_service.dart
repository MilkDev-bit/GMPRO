/// @file lib/core/storage/local_cache_service.dart
/// @description Servicio de Caché Local Efímero y Persistente (Memoria + Almacenamiento seguro/JSON).
/// Permite el fallback automático cuando peticiones a catálogos o recomendaciones dietéticas
/// fallan por falta de conectividad o caídas del servidor.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class CachedResponse {
  final dynamic data;
  final DateTime timestamp;
  final String path;

  CachedResponse({
    required this.data,
    required this.timestamp,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'path': path,
      };

  factory CachedResponse.fromJson(Map<String, dynamic> json) {
    return CachedResponse(
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp'] as String),
      path: json['path'] as String? ?? '',
    );
  }

  /// Verifica si la entrada ha expirado según el TTL otorgado (por defecto 48 horas)
  bool isExpired({Duration ttl = const Duration(hours: 48)}) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

class LocalCacheService {
  final SecureStorageService _storageService;
  
  /// Caché en memoria rápida L1 (clave -> CachedResponse) para acceso ultra-veloz en sesión
  final Map<String, CachedResponse> _memoryCache = {};

  /// Prefijo para claves persistidas en L2
  static const String _cacheKeyPrefix = 'gympro_cache_v1_';

  LocalCacheService({SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService();

  /// Genera una clave determinista única para una URL con sus query parameters
  String _generateKey(String path, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return path.trim().toLowerCase();
    }
    final sortedKeys = queryParameters.keys.toList()..sort();
    final queryString = sortedKeys
        .map((k) => '$k=${queryParameters[k]}')
        .join('&');
    return '${path.trim().toLowerCase()}?$queryString';
  }

  /// Guarda una respuesta exitosa en la caché L1 (memoria) y L2 (persistencia)
  Future<void> saveResponse(
    String path,
    dynamic data, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final key = _generateKey(path, queryParameters);
      final cachedItem = CachedResponse(
        data: data,
        timestamp: DateTime.now(),
        path: path,
      );

      // Guardar en L1
      _memoryCache[key] = cachedItem;

      // Guardar en L2 asíncronamente
      final jsonStr = jsonEncode(cachedItem.toJson());
      // Para persistir de forma segura sin sobrecargar, usamos almacenamiento cifrado/local
      // En producción esto se sincroniza con Hive/Isar si está inicializado.
      await _storageService.saveCacheEntry('$_cacheKeyPrefix$key', jsonStr);
      
      if (kDebugMode) {
        print('📦 [LocalCache] Guardado en caché efímero exitoso para: $key');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [LocalCache] Error al persistir entrada en caché: $e');
      }
    }
  }

  /// Intenta recuperar una respuesta localmente ante un fallo de red
  Future<dynamic> getResponse(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration ttl = const Duration(hours: 48),
  }) async {
    final key = _generateKey(path, queryParameters);

    // 1. Revisar Caché L1 (Memoria)
    if (_memoryCache.containsKey(key)) {
      final item = _memoryCache[key]!;
      if (!item.isExpired(ttl: ttl)) {
        if (kDebugMode) {
          print('⚡ [LocalCache L1] Sirviendo respuesta desde memoria para: $key');
        }
        return item.data;
      } else {
        _memoryCache.remove(key);
      }
    }

    // 2. Revisar Caché L2 (Persistida)
    try {
      final jsonStr = await _storageService.getCacheEntry('$_cacheKeyPrefix$key');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final item = CachedResponse.fromJson(map);

        if (!item.isExpired(ttl: ttl)) {
          // Repoblar L1 para futuras consultas instantáneas
          _memoryCache[key] = item;
          if (kDebugMode) {
            print('💾 [LocalCache L2] Sirviendo respuesta persistida para: $key');
          }
          return item.data;
        } else {
          await _storageService.deleteCacheEntry('$_cacheKeyPrefix$key');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [LocalCache] Error leyendo entrada persistida para $key: $e');
      }
    }

    return null;
  }

  /// Limpia la caché local (al cerrar sesión o forzar purga manual)
  Future<void> clearCache() async {
    _memoryCache.clear();
    await _storageService.clearAllCacheEntriesPrefix(_cacheKeyPrefix);
  }
}
