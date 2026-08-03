/// @file lib/features/auth/presentation/providers/recovery_provider.dart
/// @description Estado del flujo de RECUPERACIÓN/acceso alternativo cuando el
/// usuario no tiene su passkey (dispositivo nuevo, teléfono perdido):
///   • Login por contraseña            → POST /login
///   • Login por código de email (OTP) → /login/otp/request + /login/otp/verify
///   • Olvidé mi contraseña            → POST /password/forgot
///
/// Reutiliza la capa de datos (authRemoteDataSourceProvider) y, tras obtener una
/// sesión, la persiste (cacheSession) y refresca el estado global de auth
/// (checkInitialStatus) igual que el resto de flujos de login.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

enum RecoveryStatus { idle, loading, codeSent, done, error }

class RecoveryState {
  final RecoveryStatus status;
  final String email;
  final String? errorMessage;

  const RecoveryState({
    this.status = RecoveryStatus.idle,
    this.email = '',
    this.errorMessage,
  });

  bool get isLoading => status == RecoveryStatus.loading;

  RecoveryState copyWith({
    RecoveryStatus? status,
    String? email,
    String? errorMessage,
  }) =>
      RecoveryState(
        status: status ?? this.status,
        email: email ?? this.email,
        errorMessage: errorMessage,
      );
}

class RecoveryNotifier extends StateNotifier<RecoveryState> {
  final Ref _ref;
  RecoveryNotifier(this._ref) : super(const RecoveryState());

  /// Persiste la sesión emitida y marca el estado global como autenticado.
  Future<void> _persistAndAuthenticate(dynamic session) async {
    await _ref.read(authLocalDataSourceProvider).cacheSession(session);
    await _ref.read(authProvider.notifier).checkInitialStatus();
  }

  /// Login por email + contraseña. `true` si entró.
  Future<bool> loginWithPassword(String email, String password) async {
    if (state.isLoading) return false;
    state = state.copyWith(status: RecoveryStatus.loading, email: email, errorMessage: null);
    try {
      final session = await _ref
          .read(authRemoteDataSourceProvider)
          .loginWithPassword(email: email.trim(), password: password);
      await _persistAndAuthenticate(session);
      state = state.copyWith(status: RecoveryStatus.done);
      return true;
    } catch (e) {
      state = state.copyWith(status: RecoveryStatus.error, errorMessage: _msg(e));
      return false;
    }
  }

  /// Pide el código de acceso al email. Siempre "éxito" (anti-enumeration).
  Future<bool> requestLoginCode(String email) async {
    if (state.isLoading) return false;
    state = state.copyWith(status: RecoveryStatus.loading, email: email, errorMessage: null);
    try {
      await _ref.read(authRemoteDataSourceProvider).requestLoginOtp(email.trim());
      state = state.copyWith(status: RecoveryStatus.codeSent);
      return true;
    } catch (e) {
      state = state.copyWith(status: RecoveryStatus.error, errorMessage: _msg(e));
      return false;
    }
  }

  /// Valida el código de acceso y abre sesión. `true` si entró.
  Future<bool> verifyLoginCode(String code) async {
    if (state.isLoading) return false;
    state = state.copyWith(status: RecoveryStatus.loading, errorMessage: null);
    try {
      final session = await _ref
          .read(authRemoteDataSourceProvider)
          .verifyLoginOtp(email: state.email.trim(), code: code.trim());
      await _persistAndAuthenticate(session);
      state = state.copyWith(status: RecoveryStatus.done);
      return true;
    } catch (e) {
      state = state.copyWith(status: RecoveryStatus.error, errorMessage: _msg(e));
      return false;
    }
  }

  /// Dispara el email de restablecimiento de contraseña.
  Future<void> forgotPassword(String email) async {
    try {
      await _ref.read(authRemoteDataSourceProvider).forgotPassword(email.trim());
    } catch (_) {/* respuesta genérica: no revelar si el email existe */}
  }

  String _msg(Object e) {
    final s = e.toString();
    return s.contains(':') ? s.split(':').last.trim() : s;
  }
}

final recoveryProvider =
    StateNotifierProvider.autoDispose<RecoveryNotifier, RecoveryState>(
  (ref) => RecoveryNotifier(ref),
);
