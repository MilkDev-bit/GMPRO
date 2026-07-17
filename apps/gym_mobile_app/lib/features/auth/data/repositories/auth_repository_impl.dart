/// @file lib/features/auth/data/repositories/auth_repository_impl.dart
/// @description Implementación del repositorio de autenticación orquestando Remote, Local y manejo de fallos.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/passkey_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final PasskeyRemoteDataSource _passkeyDataSource;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
    required PasskeyRemoteDataSource passkeyDataSource,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource,
        _passkeyDataSource = passkeyDataSource;

  @override
  Future<Either<Failure, AuthUser>> loginWithGoogle() async {
    try {
      // 1. Obtener credencial nativa del SO Android/iOS
      final nativeCredential = await _remoteDataSource.getGoogleNativeCredential();

      // 2. Enviar al backend de GymPro para verificar y generar JWT personalizado
      final session = await _remoteDataSource.sendOAuthToBackend(nativeCredential);

      // 3. Cachar en almacenamiento cifrado por hardware
      await _localDataSource.cacheSession(session);

      return Right(session);
    } on UserCancelledException catch (e) {
      return Left(UserCancelledFailure(e.message));
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message, statusCode: e.statusCode));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error inesperado durante login con Google: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthUser>> loginWithApple() async {
    try {
      // 1. Abrir diálogo nativo con Face ID / Touch ID
      final nativeCredential = await _remoteDataSource.getAppleNativeCredential();

      // 2. Enviar idToken al backend para emisión de JWT
      final session = await _remoteDataSource.sendOAuthToBackend(nativeCredential);

      // 3. Guardar en Keychain
      await _localDataSource.cacheSession(session);

      return Right(session);
    } on UserCancelledException catch (e) {
      return Left(UserCancelledFailure(e.message));
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message, statusCode: e.statusCode));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error inesperado durante login con Apple: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthUser>> loginWithPasskey({String? email}) async {
    try {
      final session = await _passkeyDataSource.loginWithPasskeyNative(email: email);
      await _localDataSource.cacheSession(session);
      return Right(session);
    } on UserCancelledException catch (e) {
      return Left(UserCancelledFailure(e.message));
    } on BiometricNotAvailableException catch (e) {
      return Left(BiometricNotAvailableFailure(e.message));
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message, statusCode: e.statusCode));
    } on PasskeyException catch (e) {
      return Left(PasskeyAuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error inesperado al iniciar sesión por Passkey: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> registerPasskey() async {
    try {
      final credentialId = await _passkeyDataSource.registerPasskeyNative();
      return Right(credentialId);
    } on UserCancelledException catch (e) {
      return Left(UserCancelledFailure(e.message));
    } on BiometricNotAvailableException catch (e) {
      return Left(BiometricNotAvailableFailure(e.message));
    } on PasskeyException catch (e) {
      return Left(PasskeyAuthFailure(e.message));
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message, statusCode: e.statusCode));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error inesperado registrando Passkey: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthUser?>> getCurrentUser() async {
    try {
      final accessToken = await _localDataSource.getCachedAccessToken();
      final userDataMap = await _localDataSource.getCachedUserData();

      if (accessToken != null && accessToken.isNotEmpty && userDataMap != null) {
        return Right(
          AuthUser(
            id: userDataMap['id']?.toString() ?? '',
            email: userDataMap['email']?.toString() ?? '',
            nombre: userDataMap['nombre']?.toString() ?? 'Socio',
            apellidoPaterno: userDataMap['apellido_paterno']?.toString() ?? 'GymPro',
            rol: userDataMap['rol']?.toString() ?? 'miembro',
            emailVerificado: userDataMap['email_verificado'] == true,
            accessToken: accessToken,
          ),
        );
      }
      return const Right(null);
    } catch (e) {
      return Left(PlatformFailure('Error leyendo almacenamiento seguro: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await _remoteDataSource.logoutRemote();
      await _localDataSource.clearSession();
      return const Right(null);
    } catch (_) {
      // Si falla la revocación remota (ej. offline), forzar borrado local para proteger el dispositivo
      await _localDataSource.clearSession();
      return const Right(null);
    }
  }
}
