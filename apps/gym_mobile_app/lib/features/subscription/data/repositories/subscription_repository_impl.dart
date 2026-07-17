/// @file lib/features/subscription/data/repositories/subscription_repository_impl.dart
/// @description Implementación de SubscriptionRepository en Clean Architecture.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_subscription.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../datasources/subscription_remote_data_source.dart';

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  final SubscriptionRemoteDataSource _remoteDataSource;

  SubscriptionRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, UserSubscription>> getSubscriptionStatus() async {
    try {
      final subscription = await _remoteDataSource.fetchSubscriptionStatus();
      return Right(subscription);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(PlatformFailure('Error obteniendo estado de suscripción: $e'));
    }
  }
}
