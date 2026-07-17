/// @file lib/features/payment/domain/usecases/create_checkout_session_usecase.dart
/// @description Caso de uso en Clean Architecture para crear la sesión de pago de Stripe.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/payment_repository.dart';

class CreateCheckoutSessionUseCase {
  final PaymentRepository _repository;

  CreateCheckoutSessionUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    return await _repository.createCheckoutSession(
      priceId: priceId,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );
  }
}
