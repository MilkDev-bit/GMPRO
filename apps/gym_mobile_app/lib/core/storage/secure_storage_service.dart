/// @file lib/core/storage/secure_storage_service.dart
/// @description Almacenamiento cifrado en hardware (iOS Keychain & Android Keystore) con flutter_secure_storage.

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                // Si el Keystore se corrompe (p.ej. tras restaurar el dispositivo),
                // resetea el store en vez de lanzar y bloquear la app.
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                // first_unlock_this_device = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly:
                //   • ThisDeviceOnly → el ítem NO se incluye en backups (iCloud/iTunes)
                //     ni se migra a otro dispositivo → el refresh token no es exfiltrable
                //     vía backup ni restaurable en un equipo del atacante.
                //   • AfterFirstUnlock → sigue accesible en segundo plano tras el primer
                //     desbloqueo (necesario para refresh de sesión sin re-login).
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  /// Guarda el par de tokens JWT y la sesión en el hardware cifrado.
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userData,
  }) async {
    await Future.wait([
      _storage.write(key: AppConfig.keyAccessToken, value: accessToken),
      _storage.write(key: AppConfig.keyRefreshToken, value: refreshToken),
      _storage.write(key: AppConfig.keyUserData, value: jsonEncode(userData)),
    ]);
  }

  /// Actualiza SOLO el par de tokens tras un refresh (preserva userData).
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: AppConfig.keyAccessToken, value: accessToken),
      _storage.write(key: AppConfig.keyRefreshToken, value: refreshToken),
    ]);
  }

  /// Obtiene el access token activo.
  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConfig.keyAccessToken);
  }

  /// Obtiene el refresh token guardado.
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.keyRefreshToken);
  }

  /// Guarda el perfil de dieta (objetivo, peso, estatura, edad, actividad).
  Future<void> saveDietProfile(Map<String, dynamic> profile) async {
    await _storage.write(key: AppConfig.keyDietProfile, value: jsonEncode(profile));
  }

  /// Recupera el perfil de dieta persistido, o null si aún no se ha configurado.
  Future<Map<String, dynamic>?> getDietProfile() async {
    final jsonStr = await _storage.read(key: AppConfig.keyDietProfile);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Guarda el perfil de entrenamiento (objetivo, nivel, días/semana, lesiones).
  Future<void> saveWorkoutProfile(Map<String, dynamic> profile) async {
    await _storage.write(key: AppConfig.keyWorkoutProfile, value: jsonEncode(profile));
  }

  /// Recupera el perfil de entrenamiento persistido, o null si no se ha configurado.
  Future<Map<String, dynamic>?> getWorkoutProfile() async {
    final jsonStr = await _storage.read(key: AppConfig.keyWorkoutProfile);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Guarda la última dieta generada (JSON crudo de la respuesta del ai-service).
  Future<void> saveDietPlan(Map<String, dynamic> plan) async {
    await _storage.write(key: AppConfig.keyDietPlan, value: jsonEncode(plan));
  }

  /// Recupera la última dieta persistida, o null si aún no se ha generado.
  Future<Map<String, dynamic>?> getDietPlan() async {
    final jsonStr = await _storage.read(key: AppConfig.keyDietPlan);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Borra la dieta persistida (p. ej. al cerrar sesión).
  Future<void> clearDietPlan() async {
    await _storage.delete(key: AppConfig.keyDietPlan);
  }

  /// Guarda la última rutina generada (JSON crudo de la respuesta del ai-service).
  Future<void> saveWorkoutPlan(Map<String, dynamic> plan) async {
    await _storage.write(key: AppConfig.keyWorkoutPlan, value: jsonEncode(plan));
  }

  /// Recupera la última rutina persistida, o null si aún no se ha generado.
  Future<Map<String, dynamic>?> getWorkoutPlan() async {
    final jsonStr = await _storage.read(key: AppConfig.keyWorkoutPlan);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Borra la rutina persistida (p. ej. al cerrar sesión).
  Future<void> clearWorkoutPlan() async {
    await _storage.delete(key: AppConfig.keyWorkoutPlan);
  }

  /// Guarda (o borra, si es null) la ruta local de la foto de perfil.
  Future<void> saveAvatarPath(String? path) async {
    if (path == null || path.isEmpty) {
      await _storage.delete(key: AppConfig.keyAvatarPath);
    } else {
      await _storage.write(key: AppConfig.keyAvatarPath, value: path);
    }
  }

  /// Recupera la ruta local de la foto de perfil, o null si no se ha elegido.
  Future<String?> getAvatarPath() async {
    final p = await _storage.read(key: AppConfig.keyAvatarPath);
    return (p != null && p.isNotEmpty) ? p : null;
  }

  /// Obtiene el mapa del perfil de usuario almacenado localmente.
  Future<Map<String, dynamic>?> getUserData() async {
    const key = AppConfig.keyUserData;
    final jsonStr = await _storage.read(key: key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Verifica si existe una sesión activa y válida en hardware.
  Future<bool> hasActiveSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Guarda una entrada de caché local en el almacenamiento.
  Future<void> saveCacheEntry(String key, String jsonValue) async {
    await _storage.write(key: key, value: jsonValue);
  }

  /// Recupera una entrada de caché almacenada previamente.
  Future<String?> getCacheEntry(String key) async {
    return await _storage.read(key: key);
  }

  /// Elimina una entrada específica de caché.
  Future<void> deleteCacheEntry(String key) async {
    await _storage.delete(key: key);
  }

  /// Borra todas las entradas de caché que comiencen con el prefijo dado.
  Future<void> clearAllCacheEntriesPrefix(String prefix) async {
    try {
      final allEntries = await _storage.readAll();
      final keysToDelete = allEntries.keys.where((k) => k.startsWith(prefix));
      for (final k in keysToDelete) {
        await _storage.delete(key: k);
      }
    } catch (_) {}
  }

  /// Elimina por completo todas las credenciales y tokens al cerrar sesión.
  Future<void> clearAuth() async {
    await Future.wait([
      _storage.delete(key: AppConfig.keyAccessToken),
      _storage.delete(key: AppConfig.keyRefreshToken),
      _storage.delete(key: AppConfig.keyUserData),
    ]);
  }
}
