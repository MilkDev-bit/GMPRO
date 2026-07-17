/// @file lib/features/auth/data/datasources/auth_local_data_source.dart
/// @description Fuente de datos local en hardware (Keychain/Keystore) para persistencia de sesión JWT.

import '../../../../core/storage/secure_storage_service.dart';
import '../models/auth_response_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheSession(AuthResponseModel session);
  Future<Map<String, dynamic>?> getCachedUserData();
  Future<String?> getCachedAccessToken();
  Future<void> clearSession();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final SecureStorageService _storageService;

  AuthLocalDataSourceImpl(this._storageService);

  @override
  Future<void> cacheSession(AuthResponseModel session) async {
    await _storageService.saveAuthTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      userData: session.toUserDataMap(),
    );
  }

  @override
  Future<Map<String, dynamic>?> getCachedUserData() async {
    return await _storageService.getUserData();
  }

  @override
  Future<String?> getCachedAccessToken() async {
    return await _storageService.getAccessToken();
  }

  @override
  Future<void> clearSession() async {
    await _storageService.clearAuth();
  }
}
