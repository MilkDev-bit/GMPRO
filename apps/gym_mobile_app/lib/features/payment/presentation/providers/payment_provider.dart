/// @file lib/features/payment/presentation/providers/payment_provider.dart
/// @description Provider para iniciar el pago real con Stripe Checkout en el navegador nativo.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_client.dart';
import '../../data/datasources/payment_remote_data_source.dart';
import '../../data/repositories/payment_repository_impl.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/usecases/create_checkout_session_usecase.dart';

// ── Inyección de Dependencias ────────────────────────────────────────────────
final paymentRemoteDataSourceProvider = Provider<PaymentRemoteDataSource>((ref) {
  return PaymentRemoteDataSourceImpl(ref.watch(apiClientProvider));
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepositoryImpl(ref.watch(paymentRemoteDataSourceProvider));
});

final createCheckoutSessionUseCaseProvider = Provider<CreateCheckoutSessionUseCase>((ref) {
  return CreateCheckoutSessionUseCase(ref.watch(paymentRepositoryProvider));
});

// ── Estado de Pago ───────────────────────────────────────────────────────────
enum PaymentCheckoutStatus { initial, loading, success, error }

class PaymentCheckoutState {
  final PaymentCheckoutStatus status;
  final String? errorMessage;

  const PaymentCheckoutState({
    this.status = PaymentCheckoutStatus.initial,
    this.errorMessage,
  });
}

class PaymentNotifier extends StateNotifier<PaymentCheckoutState> {
  final CreateCheckoutSessionUseCase _createCheckoutSession;

  PaymentNotifier(this._createCheckoutSession) : super(const PaymentCheckoutState());

  /// Inicia el flujo real de Stripe Checkout en modo de prueba o producción.
  Future<bool> launchStripeCheckout({
    String priceId = 'price_test_vip_ai_coach', // ID de precio en entorno Stripe Test Mode
  }) async {
    if (state.status == PaymentCheckoutStatus.loading) return false;
    state = const PaymentCheckoutState(status: PaymentCheckoutStatus.loading);

    final result = await _createCheckoutSession(
      priceId: priceId,
      successUrl: 'gympro://payment/success',
      cancelUrl: 'gympro://payment/cancel',
    );

    return await result.fold(
      (failure) {
        state = PaymentCheckoutState(
          status: PaymentCheckoutStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
      (checkoutUrl) async {
        final uri = Uri.tryParse(checkoutUrl);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          state = const PaymentCheckoutState(status: PaymentCheckoutStatus.success);
          return true;
        } else {
          state = const PaymentCheckoutState(
            status: PaymentCheckoutStatus.error,
            errorMessage: 'No fue posible abrir el navegador para la pasarela de pago Stripe.',
          );
          return false;
        }
      },
    );
  }
}

final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentCheckoutState>((ref) {
  return PaymentNotifier(ref.watch(createCheckoutSessionUseCaseProvider));
});
