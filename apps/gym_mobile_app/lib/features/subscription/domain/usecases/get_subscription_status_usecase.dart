/// @file lib/features/subscription/domain/usecases/get_subscription_status_usecase.dart
/// @description Caso de uso para obtener el estatus de membresía desde el microservicio.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_subscription.dart';
import '../repositories/subscription_repository.dart';

class GetSubscriptionStatusUseCase {
  final SubscriptionRepository _repository;

  GetSubscriptionStatusUseCase(this._repository);

  Future<Either<Failure, UserSubscription>> call() async {
    return await _repository.getSubscriptionStatus();
  }
}
