/// @file lib/features/auth/data/datasources/passkey_remote_data_source.dart
/// @description Fuente de datos para interactuar con la biometría nativa (PasskeyAuthenticator)
/// y sincronizar desafíos FIDO2 con los endpoints del auth-service en Railway.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/auth_response_model.dart';

abstract class PasskeyRemoteDataSource {
  /// Registra una nueva Passkey vinculando el chip de seguridad con la cuenta logeada.
  Future<String> registerPasskeyNative();

  /// Autentica al usuario sin contraseña usando el chip biométrico nativo y devuelve sesión JWT.
  Future<AuthResponseModel> loginWithPasskeyNative({String? email});
}

class PasskeyRemoteDataSourceImpl implements PasskeyRemoteDataSource {
  final ApiClient _apiClient;
  final PasskeyAuthenticator _authenticator;

  PasskeyRemoteDataSourceImpl(
    this._apiClient, {
    PasskeyAuthenticator? authenticator,
  }) : _authenticator = authenticator ?? PasskeyAuthenticator();

  @override
  Future<String> registerPasskeyNative() async {
    try {
      // 1. Verificar disponibilidad biométrica y de hardware en el dispositivo
      final availability = _authenticator.getAvailability();
      try {
        final webCheck = await availability.web();
        if (!webCheck.hasPasskeySupport) {
          // No soportado en web
        }
      } catch (_) {}

      // 2. Solicitar opciones de desafío (challenge) al backend
      final optionsRes = await _apiClient.post('/passkey/register-options');
      if (optionsRes.statusCode != 200 || optionsRes.data == null || optionsRes.data['data'] == null) {
        throw const PasskeyException('No se pudieron obtener las opciones de desafío criptográfico.');
      }

      final optionsMap = Map<String, dynamic>.from(optionsRes.data['data']);

      // 3. Invocar al prompt biométrico nativo del SO (Face ID / Android StrongBox)
      final registerRequest = RegisterRequestType.fromJson(optionsMap);
      final registerResponse = await _authenticator.register(registerRequest);

      // 4. Enviar la credencial firmada de regreso al servidor para validación webauthn
      final verifyRes = await _apiClient.post(
        '/passkey/verify-register',
        data: {
          'response': registerResponse.toJson(),
          'deviceName': 'Smartphone GymPro App',
        },
      );

      if (verifyRes.statusCode == 201 && verifyRes.data != null) {
        final data = verifyRes.data['data'];
        return data?['credentialID']?.toString() ?? 'Passkey Registrada';
      } else {
        throw const PasskeyException('El servidor no pudo validar la firma criptográfica de la Passkey.');
      }
    } on PasskeyAuthCancelledException {
      throw const UserCancelledException('El usuario canceló el registro biométrico de la Passkey.');
    } on NoCredentialsAvailableException {
      throw const BiometricNotAvailableException('No hay credenciales disponibles en el dispositivo.');
    } on DeviceNotSupportedException {
      throw const BiometricNotAvailableException('El dispositivo o sistema operativo actual no soporta Passkeys.');
    } on PlatformException catch (e) {
      if (e.code == 'cancelled' || e.code.contains('CANCELED')) {
        throw const UserCancelledException('Registro de Passkey cancelado.');
      }
      throw PasskeyException('Error nativo biométrico: ${e.message ?? e.code}');
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error']?.toString() ?? 'Error al conectar con el servicio de Passkeys.';
      throw PasskeyException(errorMsg);
    } catch (e) {
      if (e is UserCancelledException || e is BiometricNotAvailableException || e is PasskeyException) {
        rethrow;
      }
      throw PasskeyException('Fallo inesperado durante el registro de Passkey: $e');
    }
  }

  @override
  Future<AuthResponseModel> loginWithPasskeyNative({String? email}) async {
    try {
      // 1. Solicitar desafío de login al backend (/passkey/login-options)
      final optionsRes = await _apiClient.post(
        '/passkey/login-options',
        data: email != null ? {'email': email} : {},
      );

      if (optionsRes.statusCode != 200 || optionsRes.data == null || optionsRes.data['data'] == null) {
        throw const PasskeyException('No se pudo iniciar el desafío de autenticación por Passkey.');
      }

      final optionsMap = Map<String, dynamic>.from(optionsRes.data['data']);

      // 2. Invocar autenticación biométrica nativa de iOS / Android
      final authRequest = AuthenticateRequestType.fromJson(optionsMap);
      final authResponse = await _authenticator.authenticate(authRequest);

      // 3. Enviar firma verificada al servidor para validación y emisión de JWT.
      //    Se reenvía el `challenge` original: en login usernameless (sin email)
      //    el backend no puede reconstruir la key `login:<userId>`, pero SÍ
      //    recupera el reto por su valor (fallback req.body.challenge). Para el
      //    login con email es inocuo (allí usa login:<userId>).
      final verifyRes = await _apiClient.post(
        '/passkey/verify-login',
        data: {
          'response': authResponse.toJson(),
          if (email != null) 'email': email,
          if (optionsMap['challenge'] != null) 'challenge': optionsMap['challenge'],
        },
      );

      if (verifyRes.statusCode == 200 && verifyRes.data != null && verifyRes.data['data'] != null) {
        return AuthResponseModel.fromJson(verifyRes.data['data']);
      } else {
        throw const AuthException('Verificación biométrica rechazada por el servidor.');
      }
    } on PasskeyAuthCancelledException {
      throw const UserCancelledException('Autenticación por Passkey cancelada por el usuario.');
    } on NoCredentialsAvailableException {
      throw const BiometricNotAvailableException('No se encontraron Passkeys guardadas para este usuario en el dispositivo.');
    } on DeviceNotSupportedException {
      throw const BiometricNotAvailableException('Hardware biométrico no disponible en este dispositivo.');
    } on PlatformException catch (e) {
      if (e.code == 'cancelled' || e.code.contains('CANCELED')) {
        throw const UserCancelledException('Inicio de sesión cancelado.');
      }
      throw PasskeyException('Fallo nativo de verificación: ${e.message ?? e.code}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 404) {
        final msg = e.response?.data?['error']?.toString() ?? 'Passkey inválida o no registrada.';
        throw AuthException(msg, statusCode: e.response?.statusCode);
      }
      throw ServerException('Error de conexión con el backend de identidad: ${e.message}');
    } catch (e) {
      if (e is UserCancelledException || e is BiometricNotAvailableException || e is AuthException || e is ServerException || e is PasskeyException) {
        rethrow;
      }
      throw PasskeyException('Error al autenticar con Passkey: $e');
    }
  }
}
