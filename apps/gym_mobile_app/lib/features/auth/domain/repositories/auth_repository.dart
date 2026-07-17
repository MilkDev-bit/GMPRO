/// @file lib/features/auth/domain/repositories/auth_repository.dart
/// @description Contrato abstracto del repositorio de autenticación para Clean Architecture.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';

abstract class AuthRepository {
  /// Inicia sesión o registra al usuario mediante cuenta nativa Google Sign-In.
  Future<Either<Failure, AuthUser>> loginWithGoogle();

  /// Inicia sesión o registra al usuario mediante Apple ID Sign-In.
  Future<Either<Failure, AuthUser>> loginWithApple();

  /// Inicia sesión sin contraseña mediante llave de acceso Passkey (WebAuthn / FIDO2).
  Future<Either<Failure, AuthUser>> loginWithPasskey({String? email});

  /// Registra y vincula una nueva Passkey biométrica al usuario actual en el chip de seguridad del teléfono.
  Future<Either<Failure, String>> registerPasskey();

  /// Verifica si el usuario actual tiene un token guardado válido en flutter_secure_storage.
  Future<Either<Failure, AuthUser?>> getCurrentUser();

  /// Revoca el token en el backend y limpia el hardware storage.
  Future<Either<Failure, void>> logout();
}
