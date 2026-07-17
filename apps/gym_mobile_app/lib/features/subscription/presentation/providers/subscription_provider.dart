/// @file lib/features/subscription/presentation/providers/subscription_provider.dart
/// @description Provider de Riverpod para gestionar y observar reactivamente el estatus de membresía del usuario.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/subscription_remote_data_source.dart';
import '../../data/repositories/subscription_repository_impl.dart';
import '../../domain/entities/user_subscription.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../../domain/usecases/get_subscription_status_usecase.dart';

// ── Inyección de Dependencias ────────────────────────────────────────────────
final subscriptionRemoteDataSourceProvider = Provider<SubscriptionRemoteDataSource>((ref) {
  return SubscriptionRemoteDataSourceImpl(ref.watch(apiClientProvider));
});

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepositoryImpl(ref.watch(subscriptionRemoteDataSourceProvider));
});

final getSubscriptionStatusUseCaseProvider = Provider<GetSubscriptionStatusUseCase>((ref) {
  return GetSubscriptionStatusUseCase(ref.watch(subscriptionRepositoryProvider));
});

// ── Notificador de Estado Async para la Membresía ────────────────────────────
class SubscriptionNotifier extends StateNotifier<AsyncValue<UserSubscription>> {
  final GetSubscriptionStatusUseCase _getSubscriptionStatus;

  SubscriptionNotifier(this._getSubscriptionStatus) : super(const AsyncValue.loading()) {
    fetchSubscription();
  }

  /// Consulta el estatus de membresía contra el microservicio.
  Future<void> fetchSubscription() async {
    state = const AsyncValue.loading();
    final result = await _getSubscriptionStatus();
    result.fold(
      (failure) {
        // Si falló por 402 Payment Required u offline, asumimos estado past_due por seguridad
        state = AsyncValue.data(
          UserSubscription(
            status: 'past_due',
            validoHasta: DateTime.now().subtract(const Duration(days: 1)),
            planName: 'Suscripción Inactiva / Vencida',
            metodoPago: 'none',
          ),
        );
      },
      (subscription) => state = AsyncValue.data(subscription),
    );
  }

  /// Permite actualizar manualmente en memoria si el usuario renueva en mostrador / efectivo.
  void setManualStatus(UserSubscription newSubscription) {
    state = AsyncValue.data(newSubscription);
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, AsyncValue<UserSubscription>>((ref) {
  return SubscriptionNotifier(ref.watch(getSubscriptionStatusUseCaseProvider));
});

/// Provider auxiliar reactivo que retorna true si el usuario actual tiene derecho a entrar al gym e IA.
final isAccessValidProvider = Provider<bool>((ref) {
  final subAsync = ref.watch(subscriptionProvider);
  return subAsync.maybeWhen(
    data: (sub) => sub.isAccessValid,
    orElse: () => false,
  );
});
