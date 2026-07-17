/// @file lib/features/qr_access/data/repositories/qr_access_repository_impl.dart
/// @description Implementación de QrAccessRepository gestionando excepciones 402/500 y devolviendo Failures.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/access_qr_token.dart';
import '../../domain/repositories/qr_access_repository.dart';
import '../datasources/qr_access_remote_data_source.dart';

class QrAccessRepositoryImpl implements QrAccessRepository {
  final QrAccessRemoteDataSource _remoteDataSource;

  QrAccessRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, AccessQrToken>> generateDynamicQr() async {
    try {
      final token = await _remoteDataSource.fetchNewDynamicQr();
      return Right(token);
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message, statusCode: e.statusCode));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error generando token QR: $e'));
    }
  }
}
