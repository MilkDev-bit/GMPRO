import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/auth_response_model.dart';
import '../models/oauth_credential_model.dart';

abstract class AuthRemoteDataSource {
  Future<OAuthCredentialModel> getAppleNativeCredential();

  Future<OAuthCredentialModel> getGoogleNativeCredential();

  Future<AuthResponseModel> sendOAuthToBackend(OAuthCredentialModel credential);

  Future<void> logoutRemote();

  /// Login por email + contraseña (/login). Recuperación en dispositivo nuevo.
  Future<AuthResponseModel> loginWithPassword({required String email, required String password});

  /// Pide un código OTP de acceso al email (/login/otp/request). No revela si existe.
  Future<void> requestLoginOtp(String email);

  /// Valida el código de acceso y devuelve sesión (/login/otp/verify).
  Future<AuthResponseModel> verifyLoginOtp({required String email, required String code});

  /// Dispara el email de restablecimiento de contraseña (/password/forgot).
  Future<void> forgotPassword(String email);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  // Web Client ID (OAuth 2.0 tipo "Web") requerido en ANDROID para que Google
  // devuelva un idToken NO nulo (el backend lo verifica). Se inyecta por
  // --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com para no
  // hardcodear el valor en el repo. Sin él, en Android el idToken sale null.
  static const String _kGoogleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  final ApiClient _apiClient;
  final GoogleSignIn _googleSignIn;

  AuthRemoteDataSourceImpl(
    this._apiClient, {
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email', 'profile'],
              serverClientId:
                  _kGoogleWebClientId.isEmpty ? null : _kGoogleWebClientId,
            );

  @override
  Future<OAuthCredentialModel> getAppleNativeCredential() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw const AuthException('No se recibió el token de identidad nativo de Apple ID.');
      }

      // El email puede venir nulo en reintentos de login si Apple ya lo autorizó en el pasado.
      // Si viene nulo, pasamos el userIdentifier de Apple como fallback o identificador.
      final email = credential.email ?? '${credential.userIdentifier}@privaterelay.appleid.com';
      final nombre = credential.givenName ?? 'Socio';
      final apellidoPaterno = credential.familyName ?? 'Apple';

      return OAuthCredentialModel(
        provider: 'apple',
        idToken: identityToken,
        email: email,
        nombre: nombre,
        apellidoPaterno: apellidoPaterno,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled || e.code.toString().contains('canceled')) {
        throw const UserCancelledException('Inicio de sesión con Apple cancelado por el usuario.');
      }
      throw AuthException('Error de autorización con Apple: ${e.message}');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED' || e.code == 'sign_in_canceled') {
        throw const UserCancelledException('Inicio de sesión cancelado.');
      }
      throw AuthException('Error nativo de plataforma: ${e.message}');
    } catch (e) {
      if (e is UserCancelledException || e is AuthException) rethrow;
      throw AuthException('No fue posible conectar con el servicio nativo de Apple ID: $e');
    }
  }

  @override
  Future<OAuthCredentialModel> getGoogleNativeCredential() async {
    try {
      // Si ya había una cuenta seleccionada previamente en memoria, desconectar para elegir limpiamente
      await _googleSignIn.signOut();

      final account = await _googleSignIn.signIn();
      if (account == null) {
        // El usuario cerró el modal o presionó la flecha de atrás sin elegir cuenta
        throw const UserCancelledException('El usuario cerró la selección de cuenta de Google.');
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('No se obtuvo el idToken firmado de los servidores de Google.');
      }

      // Dividir displayName si existe
      final names = (account.displayName ?? 'Socio GymPro').split(' ');
      final nombre = names.first;
      final apellidoPaterno = names.length > 1 ? names.sublist(1).join(' ') : 'Google';

      return OAuthCredentialModel(
        provider: 'google',
        idToken: idToken,
        email: account.email,
        nombre: nombre,
        apellidoPaterno: apellidoPaterno,
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED' || e.code == 'sign_in_canceled' || e.code == 'sign_in_failed') {
        // En Android a veces al pulsar atrás lanza sign_in_failed o CANCELED
        if (e.message?.toLowerCase().contains('cancel') == true || e.code == 'CANCELED') {
          throw const UserCancelledException('Inicio de sesión con Google cancelado.');
        }
      }
      throw AuthException('Error en Google Sign-In nativo: ${e.message}');
    } catch (e) {
      if (e is UserCancelledException || e is AuthException) rethrow;
      throw AuthException('No fue posible autenticar con Google Sign-In: $e');
    }
  }

  @override
  Future<AuthResponseModel> sendOAuthToBackend(OAuthCredentialModel credential) async {
    try {
      final response = await _apiClient.post(
        '/oauth-login',
        data: credential.toJson(),
      );

      if (response.statusCode == 200 && response.data != null) {
        return AuthResponseModel.fromJson(response.data);
      } else {
        throw AuthException('Respuesta inesperada del servidor GymPro (${response.statusCode}).');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final errorMsg = e.response?.data?['error']?.toString() ??
            'Rechazado por el servidor (${e.response?.statusCode}).';
        throw AuthException(errorMsg, statusCode: e.response?.statusCode);
      } else {
        throw const ServerException('No se pudo establecer conexión con auth-service en Railway.');
      }
    } catch (e) {
      if (e is AuthException || e is ServerException) rethrow;
      throw ServerException('Error procesando autenticación: $e');
    }
  }

  @override
  Future<void> logoutRemote() async {
    try {
      await _apiClient.post('/logout');
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignorar errores al desconectar si el token ya expiró
    }
  }

  @override
  Future<AuthResponseModel> loginWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _apiClient.post('/login', data: {'email': email, 'password': password});
      if (res.statusCode == 200 && res.data != null) {
        return AuthResponseModel.fromJson(res.data['data'] ?? res.data);
      }
      throw AuthException('Respuesta inesperada del servidor (${res.statusCode}).');
    } on DioException catch (e) {
      final msg = e.response?.data?['error']?.toString() ??
          'No se pudo iniciar sesión. Verifica tus credenciales.';
      throw AuthException(msg, statusCode: e.response?.statusCode);
    }
  }

  @override
  Future<void> requestLoginOtp(String email) async {
    try {
      // Siempre 200 (respuesta genérica anti-enumeration); no lanzamos por 4xx de contenido.
      await _apiClient.post('/login/otp/request', data: {'email': email});
    } on DioException catch (e) {
      // Solo propagamos errores de red/servidor reales.
      if (e.response == null) {
        throw const ServerException('No se pudo contactar el servidor.');
      }
    }
  }

  @override
  Future<AuthResponseModel> verifyLoginOtp({
    required String email,
    required String code,
  }) async {
    try {
      final res = await _apiClient.post('/login/otp/verify', data: {'email': email, 'codigo': code});
      if (res.statusCode == 200 && res.data != null) {
        return AuthResponseModel.fromJson(res.data['data'] ?? res.data);
      }
      throw const AuthException('Código inválido.');
    } on DioException catch (e) {
      final msg = e.response?.data?['error']?.toString() ?? 'Código inválido o expirado.';
      throw AuthException(msg, statusCode: e.response?.statusCode);
    }
  }

  @override
  Future<void> forgotPassword(String email) async {
    try {
      await _apiClient.post('/password/forgot', data: {'email': email});
    } on DioException catch (e) {
      if (e.response == null) {
        throw const ServerException('No se pudo contactar el servidor.');
      }
      // 4xx de contenido → respuesta genérica (no revelar si el email existe).
    }
  }
}
