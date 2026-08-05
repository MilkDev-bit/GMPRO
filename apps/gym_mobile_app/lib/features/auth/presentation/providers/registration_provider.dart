/// @file lib/features/auth/presentation/providers/registration_provider.dart
/// @description Estado reactivo (Riverpod) del flujo de alta multi-paso passwordless.
/// Orquesta datos personales → correo → verificación OTP → registro de Passkey.
///
/// NOTA DE INTEGRACIÓN: los métodos marcados con `// TODO(backend)` deben
/// conectarse a los endpoints de `auth-service` (Node/Zod) cuando estén listos:
///   POST /register            → crea el socio y dispara el envío de OTP
///   POST /otp/verify          → valida el código y habilita el registro de Passkey
/// Mientras tanto simulan la latencia de red para mantener la UX end-to-end.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/auth_response_model.dart';
import 'auth_provider.dart';

// ── Enumeraciones del flujo ──────────────────────────────────────────────────
enum RegistrationStep { personalInfo, email, otp, done }

enum RegistrationStatus { idle, submitting, error }

// ── Estado inmutable ─────────────────────────────────────────────────────────
class RegistrationState {
  final RegistrationStep step;
  final RegistrationStatus status;
  final String fullName;
  final DateTime? birthDate;
  final String phone;
  final String email;
  final String? errorMessage;
  final bool otpError;

  /// True cuando el código OTP ya se validó y la sesión quedó abierta. Evita
  /// re-verificar (el código se consume) al reintentar el registro de Passkey.
  final bool otpVerified;

  const RegistrationState({
    this.step = RegistrationStep.personalInfo,
    this.status = RegistrationStatus.idle,
    this.fullName = '',
    this.birthDate,
    this.phone = '',
    this.email = '',
    this.errorMessage,
    this.otpError = false,
    this.otpVerified = false,
  });

  bool get isSubmitting => status == RegistrationStatus.submitting;

  RegistrationState copyWith({
    RegistrationStep? step,
    RegistrationStatus? status,
    String? fullName,
    DateTime? birthDate,
    String? phone,
    String? email,
    String? errorMessage,
    bool? otpError,
    bool? otpVerified,
  }) {
    return RegistrationState(
      step: step ?? this.step,
      status: status ?? this.status,
      fullName: fullName ?? this.fullName,
      birthDate: birthDate ?? this.birthDate,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      errorMessage: errorMessage,
      otpError: otpError ?? this.otpError,
      otpVerified: otpVerified ?? this.otpVerified,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────
class RegistrationNotifier extends StateNotifier<RegistrationState> {
  final Ref _ref;

  RegistrationNotifier(this._ref) : super(const RegistrationState());

  /// Paso 1 → guarda datos personales y avanza a la captura de correo.
  void submitPersonalInfo({
    required String fullName,
    required DateTime birthDate,
    required String phone,
  }) {
    state = state.copyWith(
      fullName: fullName,
      birthDate: birthDate,
      phone: phone,
      step: RegistrationStep.email,
      status: RegistrationStatus.idle,
    );
  }

  /// Paso 2 → guarda el correo, solicita el envío del OTP y avanza.
  Future<void> submitEmail(String email) async {
    if (state.isSubmitting) return;
    state = state.copyWith(email: email, status: RegistrationStatus.submitting);

    try {
      await _requestOtp(email);
      state = state.copyWith(
        step: RegistrationStep.otp,
        status: RegistrationStatus.idle,
      );
    } catch (e) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: _registerErrorMessage(e),
      );
    }
  }

  /// Traduce el fallo de /register al mensaje real (antes se ocultaba todo tras
  /// un genérico "verifica tu correo", imposible de diagnosticar).
  String _registerErrorMessage(Object e) {
    if (e is DioException) {
      final sc = e.response?.statusCode;
      final data = e.response?.data;
      final backendMsg = (data is Map)
          ? (data['error']?.toString() ?? data['mensaje']?.toString())
          : null;
      if (sc == 409) {
        return 'Ese correo ya está registrado y verificado. Usa "Entrar con '
            'contraseña" o "Entrar con código".';
      }
      if (sc == 429) {
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Sin conexión con el servidor. Revisa tu red e inténtalo de nuevo.';
      }
      if (backendMsg != null && backendMsg.trim().isNotEmpty) return backendMsg;
      return 'No pudimos enviar el código (error $sc). Intenta de nuevo.';
    }
    return 'No pudimos enviar el código. Verifica tu correo.';
  }

  /// Paso 3 → valida el OTP y, si es correcto, vincula la Passkey biométrica.
  Future<void> verifyOtpAndRegister(String code) async {
    if (state.isSubmitting) return;
    state = state.copyWith(status: RegistrationStatus.submitting, otpError: false);

    try {
      // El OTP se valida UNA vez (consume el código y abre sesión). En reintentos
      // de Passkey ya no se re-verifica.
      if (!state.otpVerified) {
        final ok = await _verifyOtp(state.email, code);
        if (!ok) {
          state = state.copyWith(status: RegistrationStatus.idle, otpError: true);
          return;
        }
        state = state.copyWith(otpVerified: true);
      }

      // Con la sesión ya abierta (JWT en secure storage), registra la Passkey
      // (FIDO2) en el chip del móvil — el endpoint exige estar autenticado.
      final registered = await _ref.read(authProvider.notifier).registerPasskey();
      if (registered) {
        // Refleja el estado global como autenticado (lee la sesión cacheada).
        await _ref.read(authProvider.notifier).checkInitialStatus();
        state = state.copyWith(
          step: RegistrationStep.done,
          status: RegistrationStatus.idle,
        );
      } else {
        state = state.copyWith(
          status: RegistrationStatus.error,
          errorMessage: 'No se pudo vincular tu Passkey. Intenta de nuevo.',
        );
      }
    } catch (_) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Error verificando el código. Intenta de nuevo.',
      );
    }
  }

  /// Reenvía el código OTP al correo capturado.
  Future<void> resendOtp() async {
    try {
      await _requestOtp(state.email);
    } catch (_) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'No pudimos reenviar el código.',
      );
    }
  }

  /// Retrocede un paso sin perder los datos ya capturados.
  void previousStep() {
    switch (state.step) {
      case RegistrationStep.email:
        state = state.copyWith(step: RegistrationStep.personalInfo);
        break;
      case RegistrationStep.otp:
        state = state.copyWith(step: RegistrationStep.email, otpError: false);
        break;
      case RegistrationStep.personalInfo:
      case RegistrationStep.done:
        break;
    }
  }

  // ── Integración con auth-service ───────────────────────────────────────────
  // POST /register es idempotente para email no verificado (sirve para reenviar).
  Future<void> _requestOtp(String email) async {
    final api = _ref.read(apiClientProvider);
    try {
      final res = await api.post('/register', data: {
        'email': email,
        'nombre': state.fullName.trim(),
        if (state.phone.trim().isNotEmpty) 'telefono': state.phone.trim(),
        if (state.birthDate != null)
          'fecha_nacimiento':
              state.birthDate!.toIso8601String().split('T').first, // YYYY-MM-DD
      });
      debugPrint('📝 [Register] OK status=${res.statusCode} body=${res.data}');
    } on DioException catch (e) {
      debugPrint('📝 [Register] FAIL type=${e.type} status=${e.response?.statusCode} '
          'body=${e.response?.data}');
      rethrow;
    }
  }

  Future<bool> _verifyOtp(String email, String code) async {
    final api = _ref.read(apiClientProvider);
    try {
      final res = await api.post('/otp/verify', data: {
        'email': email,
        'codigo': code,
      });
      if (res.statusCode == 200 && res.data != null) {
        // /otp/verify abre sesión (access + refresh). Persistirla en el almacén
        // seguro hace que el AuthInterceptor adjunte el Bearer en la siguiente
        // llamada (registro de Passkey, que exige JWT).
        final session = AuthResponseModel.fromJson(res.data['data'] ?? res.data);
        await _ref.read(authLocalDataSourceProvider).cacheSession(session);
        return true;
      }
      return false;
    } on DioException catch (e) {
      // 400 (código inválido/expirado) o 429 (demasiados intentos) → otpError,
      // no un error genérico. Otros códigos (500, red) sí se propagan.
      final sc = e.response?.statusCode;
      if (sc == 400 || sc == 429) return false;
      rethrow;
    }
  }
}

// ── Provider global ──────────────────────────────────────────────────────────
final registrationProvider =
    StateNotifierProvider.autoDispose<RegistrationNotifier, RegistrationState>(
  (ref) => RegistrationNotifier(ref),
);
