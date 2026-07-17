/// @file lib/features/payment/domain/repositories/payment_repository.dart
/// @description Contrato del repositorio para iniciar el pago o renovación real en Stripe.

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';

abstract class PaymentRepository {
  /// Crea una sesión de pago real de Stripe Checkout y devuelve la URL del portal bancario.
  Future<Either<Failure, String>> createCheckoutSession({
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  });
}
