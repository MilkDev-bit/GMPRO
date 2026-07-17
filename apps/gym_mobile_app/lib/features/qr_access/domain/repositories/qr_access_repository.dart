/// @file lib/features/qr_access/domain/repositories/qr_access_repository.dart
/// @description Contrato del repositorio para generar el token QR criptográfico en el access-service.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/access_qr_token.dart';

abstract class QrAccessRepository {
  /// Solicita un nuevo token AES-256 de un solo uso con vigencia de 30 segundos.
  /// Puede retornar 402 Payment Required a través de un fallo específico si la membresía está vencida.
  Future<Either<Failure, AccessQrToken>> generateDynamicQr();
}
