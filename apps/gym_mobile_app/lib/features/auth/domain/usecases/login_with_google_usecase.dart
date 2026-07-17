/// @file lib/features/auth/domain/usecases/login_with_google_usecase.dart
/// @description Caso de uso para el inicio de sesión nativo de Google en la capa de dominio.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';
import '../repositories/auth_repository.dart';

class LoginWithGoogleUseCase {
  final AuthRepository _repository;

  LoginWithGoogleUseCase(this._repository);

  Future<Either<Failure, AuthUser>> call() async {
    return await _repository.loginWithGoogle();
  }
}
