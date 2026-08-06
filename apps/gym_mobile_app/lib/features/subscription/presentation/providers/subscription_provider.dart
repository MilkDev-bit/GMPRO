/// @file lib/features/subscription/presentation/providers/subscription_provider.dart
/// @description Provider de Riverpod para gestionar y observar reactivamente el estatus de membresía del usuario.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/subscription_remote_data_source.dart';
import '../../data/datasources/subscription_realtime_service.dart';
import '../../data/models/user_subscription_model.dart';
import '../../data/repositories/subscription_repository_impl.dart';
import '../../domain/entities/user_subscription.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../../domain/usecases/get_subscription_status_usecase.dart';

// ── Inyección de Dependencias ────────────────────────────────────────────────
final subscriptionRemoteDataSourceProvider = Provider<SubscriptionRemoteDataSource>((ref) {
  return SubscriptionRemoteDataSourceImpl(ref.watch(apiClientProvider));
});

final subscriptionRealtimeServiceProvider = Provider<SubscriptionRealtimeService>((ref) {
  final service = SubscriptionRealtimeService();
  ref.onDispose(service.unsubscribe);
  return service;
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
  final SubscriptionRealtimeService? _realtimeService;
  final String? _usuarioId;

  SubscriptionNotifier(
    this._getSubscriptionStatus, {
    SubscriptionRealtimeService? realtimeService,
    String? usuarioId,
  })  : _realtimeService = realtimeService,
        _usuarioId = usuarioId,
        super(const AsyncValue.loading()) {
    fetchSubscription();
    _listenRealtime();
  }

  /// Abre el canal Supabase Realtime para reaccionar a cambios de estado (p. ej.
  /// past_due → active tras un pago en mostrador) sin recargar la app.
  void _listenRealtime() {
    final id = _usuarioId;
    if (_realtimeService == null || id == null || id.isEmpty) return;
    _realtimeService.subscribe(
      usuarioId: id,
      onChanged: (UserSubscriptionModel sub) {
        // El evento de Supabase gana: refleja el estado más reciente al instante.
        state = AsyncValue.data(sub);
      },
    );
  }

  @override
  void dispose() {
    _realtimeService?.unsubscribe();
    super.dispose();
  }

  /// Consulta el estatus de membresía contra el microservicio.
  Future<void> fetchSubscription() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    final result = await _getSubscriptionStatus();
    // El provider puede haberse dispuesto durante el await (un cambio de auth
    // recrea el notifier, o un refresco encolado tras volver del pago). Sin este
    // guard: "Bad state: Tried to use SubscriptionNotifier after dispose".
    if (!mounted) return;
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
  // ID del socio autenticado para filtrar el canal Realtime a su propia fila.
  final usuarioId = ref.watch(authProvider).user?.id;
  return SubscriptionNotifier(
    ref.watch(getSubscriptionStatusUseCaseProvider),
    realtimeService: ref.watch(subscriptionRealtimeServiceProvider),
    usuarioId: usuarioId,
  );
});

/// Provider auxiliar reactivo que retorna true si el usuario actual tiene derecho a entrar al gym e IA.
final isAccessValidProvider = Provider<bool>((ref) {
  final subAsync = ref.watch(subscriptionProvider);
  return subAsync.maybeWhen(
    data: (sub) => sub.isAccessValid,
    orElse: () => false,
  );
});
