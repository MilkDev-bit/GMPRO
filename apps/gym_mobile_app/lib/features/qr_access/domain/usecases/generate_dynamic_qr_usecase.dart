/// @file lib/features/qr_access/domain/usecases/generate_dynamic_qr_usecase.dart
/// @description Caso de uso para generar un nuevo QR dinámico desde la capa de presentación.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/access_qr_token.dart';
import '../repositories/qr_access_repository.dart';

class GenerateDynamicQrUseCase {
  final QrAccessRepository _repository;

  GenerateDynamicQrUseCase(this._repository);

  Future<Either<Failure, AccessQrToken>> call() async {
    return await _repository.generateDynamicQr();
  }
}
