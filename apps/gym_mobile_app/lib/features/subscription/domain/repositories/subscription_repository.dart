/// @file lib/features/subscription/domain/repositories/subscription_repository.dart
/// @description Contrato del repositorio para consultar el estado de membresía del usuario.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_subscription.dart';

abstract class SubscriptionRepository {
  /// Obtiene el estado actual, fecha de expiración y plan de membresía del usuario.
  Future<Either<Failure, UserSubscription>> getSubscriptionStatus();
}
