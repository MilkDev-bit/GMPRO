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
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
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

  /// Obtiene el access token activo.
  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConfig.keyAccessToken);
  }

  /// Obtiene el refresh token guardado.
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.keyRefreshToken);
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

  /// Elimina por completo todas las credenciales y tokens al cerrar sesión.
  Future<void> clearAuth() async {
    await Future.wait([
      _storage.delete(key: AppConfig.keyAccessToken),
      _storage.delete(key: AppConfig.keyRefreshToken),
      _storage.delete(key: AppConfig.keyUserData),
    ]);
  }
}
