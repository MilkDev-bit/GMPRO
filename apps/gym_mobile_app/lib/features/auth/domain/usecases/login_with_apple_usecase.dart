/// @file lib/features/auth/domain/usecases/login_with_apple_usecase.dart
/// @description Caso de uso para el inicio de sesión nativo de Apple ID en la capa de dominio.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

class LoginWithAppleUseCase {
  final AuthRepository _repository;

  LoginWithAppleUseCase(this._repository);

  Future<Either<Failure, AuthUser>> call() async {
    return await _repository.loginWithApple();
  }
}
