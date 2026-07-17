/// @file lib/features/auth/domain/usecases/register_passkey_usecase.dart
/// @description Caso de uso para registrar y vincular un nuevo Passkey (FIDO2) al usuario actual en el chip del móvil.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/auth_repository.dart';

class RegisterPasskeyUseCase {
  final AuthRepository _repository;

  RegisterPasskeyUseCase(this._repository);

  Future<Either<Failure, String>> call() async {
    return await _repository.registerPasskey();
  }
}
