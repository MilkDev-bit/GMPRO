/// @file lib/features/payment/presentation/providers/payment_provider.dart
/// @description Provider para iniciar el pago real con Stripe Checkout en el navegador nativo.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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

  bool get isLoading => status == PaymentCheckoutStatus.loading;
}

class PaymentNotifier extends StateNotifier<PaymentCheckoutState> {
  final CreateCheckoutSessionUseCase _createCheckoutSession;

  PaymentNotifier(this._createCheckoutSession) : super(const PaymentCheckoutState());

  /// Abre el portal de Stripe Customer o reintenta cobro
  Future<bool> openCustomerPortal() async {
    return launchStripeCheckout();
  }

  /// Inicia el flujo real de Stripe Checkout en modo de prueba o producción.
  Future<bool> launchStripeCheckout({
    String priceId = 'mensual', // PLAN ('mensual'/'trimestral'); el backend lo mapea al Stripe Price ID real del env
  }) async {
    if (state.status == PaymentCheckoutStatus.loading) return false;
    state = const PaymentCheckoutState(status: PaymentCheckoutStatus.loading);

    // Stripe SOLO acepta http/https en success/cancel_url (el deep link
    // gympro:// fallaba la validación → 422 "URL inválida"). Usamos el dominio
    // propio gmpro.lat como URL de retorno https válida.
    final result = await _createCheckoutSession(
      priceId: priceId,
      successUrl: 'https://gmpro.lat/payment/success',
      cancelUrl: 'https://gmpro.lat/payment/cancel',
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
