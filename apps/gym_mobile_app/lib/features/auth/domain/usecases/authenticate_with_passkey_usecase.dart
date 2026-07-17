/// @file lib/features/auth/domain/usecases/authenticate_with_passkey_usecase.dart
/// @description Caso de uso para autenticación sin contraseña mediante Passkeys nativos (Face ID / Touch ID / StrongBox).

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

class AuthenticateWithPasskeyUseCase {
  final AuthRepository _repository;

  AuthenticateWithPasskeyUseCase(this._repository);

  Future<Either<Failure, AuthUser>> call({String? email}) async {
    return await _repository.loginWithPasskey(email: email);
  }
}
