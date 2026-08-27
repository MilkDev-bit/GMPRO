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
