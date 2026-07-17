/// @file lib/features/qr_access/presentation/providers/qr_access_provider.dart
/// @description Provider para generar el QR dinámico rotativo cada 30 segundos y gestionar bloqueos por adeudo.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/index.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../data/datasources/qr_access_remote_data_source.dart';
import '../../data/repositories/qr_access_repository_impl.dart';
import '../../domain/entities/access_qr_token.dart';
import '../../domain/repositories/qr_access_repository.dart';
import '../../domain/usecases/generate_dynamic_qr_usecase.dart';

// ── Inyección de Dependencias ────────────────────────────────────────────────
final qrAccessRemoteDataSourceProvider = Provider<QrAccessRemoteDataSource>((ref) {
  return QrAccessRemoteDataSourceImpl(ref.watch(apiClientProvider));
});

final qrAccessRepositoryProvider = Provider<QrAccessRepository>((ref) {
  return QrAccessRepositoryImpl(ref.watch(qrAccessRemoteDataSourceProvider));
});

final generateDynamicQrUseCaseProvider = Provider<GenerateDynamicQrUseCase>((ref) {
  return GenerateDynamicQrUseCase(ref.watch(qrAccessRepositoryProvider));
});

// ── Estado del QR Dinámico ───────────────────────────────────────────────────
enum QrStatus { initial, loading, active, paymentRequired, error }

class QrAccessState {
  final QrStatus status;
  final AccessQrToken? qrToken;
  final int secondsRemaining;
  final String? errorMessage;

  const QrAccessState({
    this.status = QrStatus.initial,
    this.qrToken,
    this.secondsRemaining = 30,
    this.errorMessage,
  });

  QrAccessState copyWith({
    QrStatus? status,
    AccessQrToken? qrToken,
    int? secondsRemaining,
    String? errorMessage,
  }) {
    return QrAccessState(
      status: status ?? this.status,
      qrToken: qrToken ?? this.qrToken,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      errorMessage: errorMessage,
    );
  }
}

// ── Notificador que maneja el Timer de 30 segundos y peticiones al API ───────
class QrAccessNotifier extends StateNotifier<QrAccessState> {
  final GenerateDynamicQrUseCase _generateDynamicQr;
  final Ref _ref;
  Timer? _countdownTimer;

  QrAccessNotifier(this._generateDynamicQr, this._ref) : super(const QrAccessState());

  /// Inicia el ciclo del código QR dinámico de 30 segundos.
  Future<void> startDynamicRefresh() async {
    final isValid = _ref.read(isAccessValidProvider);
    if (!isValid) {
      stopRefresh();
      state = state.copyWith(status: QrStatus.paymentRequired);
      return;
    }

    await _fetchNewQrToken();
    _startTicker();
  }

  /// Detiene el temporizador de refresco.
  void stopRefresh() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Gestiona el cambio en la suscripción desde los oyentes externos.
  void handleSubscriptionStatusChange(bool isAccessValid) {
    if (!isAccessValid) {
      stopRefresh();
      state = state.copyWith(status: QrStatus.paymentRequired);
    } else if (state.status == QrStatus.paymentRequired || state.status == QrStatus.initial) {
      startDynamicRefresh();
    }
  }

  /// Consulta el nuevo token encriptado AES-256 al servidor de accesos.
  Future<void> _fetchNewQrToken() async {
    if (state.status != QrStatus.active) {
      state = state.copyWith(status: QrStatus.loading);
    }

    final result = await _generateDynamicQr();
    result.fold(
      (failure) {
        if (failure is AuthFailure && failure.statusCode == 402) {
          stopRefresh();
          state = state.copyWith(status: QrStatus.paymentRequired);
        } else {
          state = state.copyWith(
            status: QrStatus.error,
            errorMessage: failure.message,
          );
        }
      },
      (token) {
        state = state.copyWith(
          status: QrStatus.active,
          qrToken: token,
          secondsRemaining: token.refreshInterval,
        );
        // Sincronizar automáticamente con Apple Watch / Wear OS
        try {
          _ref.read(wearableControllerProvider.notifier).syncQrToken(
                token: token.token,
                expiresAt: token.expiresAt,
              );
        } catch (_) {}
      },
    );
  }

  /// Ticker interno de 1 segundo que decrementa la cuenta regresiva.
  void _startTicker() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_ref.read(isAccessValidProvider)) {
        stopRefresh();
        state = state.copyWith(status: QrStatus.paymentRequired);
        return;
      }

      if (state.secondsRemaining <= 1) {
        _fetchNewQrToken();
      } else {
        state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  @override
  void dispose() {
    stopRefresh();
    super.dispose();
  }
}

final qrAccessProvider = StateNotifierProvider<QrAccessNotifier, QrAccessState>((ref) {
  final notifier = QrAccessNotifier(
    ref.watch(generateDynamicQrUseCaseProvider),
    ref,
  );

  ref.listen<AsyncValue<dynamic>>(subscriptionProvider, (previous, next) {
    next.whenData((sub) {
      notifier.handleSubscriptionStatusChange(sub.isAccessValid as bool? ?? false);
    });
  });

  return notifier;
});
