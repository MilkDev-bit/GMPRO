/// @file lib/features/payment/data/repositories/payment_repository_impl.dart
/// @description Implementación de PaymentRepository.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/payment_remote_data_source.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentRemoteDataSource _remoteDataSource;

  PaymentRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, String>> createCheckoutSession({
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      final url = await _remoteDataSource.createCheckoutSession(
        priceId: priceId,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
      );
      return Right(url);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error al iniciar el pago: $e'));
    }
  }
}
