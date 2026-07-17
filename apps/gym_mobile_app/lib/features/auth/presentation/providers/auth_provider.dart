/// @file lib/features/auth/presentation/providers/auth_provider.dart
/// @description Gestión de estado con Riverpod (StateNotifierProvider) para la autenticación en GymPro.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_with_apple_usecase.dart';
import '../../domain/usecases/login_with_google_usecase.dart';
import '../../../../core/services/notification_service.dart';

// ── Inyección de Dependencias (Providers de infraestructura y dominio) ───────
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(storageService: ref.watch(secureStorageProvider));
});

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return AuthLocalDataSourceImpl(ref.watch(secureStorageProvider));
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(ref.watch(apiClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
    localDataSource: ref.watch(authLocalDataSourceProvider),
  );
});

final loginWithGoogleUseCaseProvider = Provider<LoginWithGoogleUseCase>((ref) {
  return LoginWithGoogleUseCase(ref.watch(authRepositoryProvider));
});

final loginWithAppleUseCaseProvider = Provider<LoginWithAppleUseCase>((ref) {
  return LoginWithAppleUseCase(ref.watch(authRepositoryProvider));
});

// ── Estado de la Autenticación ───────────────────────────────────────────────
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage, // Puede ser null
    );
  }
}

// ── Notificador de Estado (Notifier) ─────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final LoginWithGoogleUseCase _loginWithGoogle;
  final LoginWithAppleUseCase _loginWithApple;
  final ApiClient _apiClient;

  AuthNotifier({
    required AuthRepository repository,
    required LoginWithGoogleUseCase loginWithGoogle,
    required LoginWithAppleUseCase loginWithApple,
    required ApiClient apiClient,
  })  : _repository = repository,
        _loginWithGoogle = loginWithGoogle,
        _loginWithApple = loginWithApple,
        _apiClient = apiClient,
        super(const AuthState());

  /// Verifica al arrancar la app si hay una sesión guardada en hardware.
  Future<void> checkInitialStatus() async {
    state = state.copyWith(status: AuthStatus.loading);
    final result = await _repository.getCurrentUser();
    result.fold(
      (failure) => state = state.copyWith(status: AuthStatus.unauthenticated),
      (user) {
        if (user != null) {
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
          _registerFCMToken(user.id);
        } else {
          state = state.copyWith(status: AuthStatus.unauthenticated);
        }
      },
    );
  }

  /// Inicia sesión nativa con Google.
  Future<void> loginWithGoogle() async {
    if (state.status == AuthStatus.loading) return;
    state = state.copyWith(status: AuthStatus.loading);

    final result = await _loginWithGoogle();
    result.fold(
      (failure) {
        if (failure is UserCancelledFailure) {
          state = state.copyWith(status: AuthStatus.unauthenticated);
        } else {
          state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: failure.message,
          );
        }
      },
      (user) {
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
        _registerFCMToken(user.id);
      },
    );
  }

  /// Inicia sesión nativa con Apple ID.
  Future<void> loginWithApple() async {
    if (state.status == AuthStatus.loading) return;
    state = state.copyWith(status: AuthStatus.loading);

    final result = await _loginWithApple();
    result.fold(
      (failure) {
        if (failure is UserCancelledFailure) {
          state = state.copyWith(status: AuthStatus.unauthenticated);
        } else {
          state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: failure.message,
          );
        }
      },
      (user) {
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
        _registerFCMToken(user.id);
      },
    );
  }

  /// Cierra sesión en backend y borra credenciales del hardware.
  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading);
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Registro de FCM Token seguro y asíncrono en segundo plano al autenticarse.
  void _registerFCMToken(String userId) {
    Future.microtask(() async {
      await NotificationServiceImpl.instance.requestPermissions();
      await NotificationServiceImpl.instance.registerDeviceTokenWithBackend(
        userId: userId,
        apiClient: _apiClient,
      );
    });
  }
}

// ── Provider Global para la UI ───────────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    repository: ref.watch(authRepositoryProvider),
    loginWithGoogle: ref.watch(loginWithGoogleUseCaseProvider),
    loginWithApple: ref.watch(loginWithAppleUseCaseProvider),
    apiClient: ref.watch(apiClientProvider),
  );
});

