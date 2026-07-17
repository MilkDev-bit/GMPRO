/// @file lib/core/errors/failures.dart
/// @description Jerarquía de fallos de dominio para Clean Architecture (Either<Failure, T>).

import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Fallo específico cuando el usuario cancela voluntariamente el flujo nativo OAuth de Apple o Google.
/// El UI interceptará este fallo para NO mostrar alertas de error intrusivas ni snackbars rojos.
class UserCancelledFailure extends Failure {
  const UserCancelledFailure([super.message = 'Inicio de sesión cancelado por el usuario.']);
}

/// Fallo cuando el backend o las credenciales devuelven un error de autenticación o bloqueo.
class AuthFailure extends Failure {
  final int? statusCode;
  const AuthFailure(super.message, {this.statusCode});

  @override
  List<Object?> get props => [message, statusCode];
}

/// Fallo de conectividad a internet o timeout de red al contactar al backend de GymPro.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Sin conexión a internet. Verifique su red.']);
}

/// Fallo en el servidor de microservicios (Error 500+ o respuesta malformada).
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Ocurrió un error en el servidor de GymPro. Intente más tarde.']);
}

/// Fallo genérico de hardware o sistema operativo.
class PlatformFailure extends Failure {
  const PlatformFailure(super.message);
}

/// Fallo cuando el hardware biométrico (Enclave Seguro / StrongBox / Face ID / Touch ID) no está disponible o soportado.
class BiometricNotAvailableFailure extends Failure {
  const BiometricNotAvailableFailure([super.message = 'Dispositivo no compatible o biometría no activada.']);
}

/// Fallo en la autenticación criptográfica de la Passkey (WebAuthn / FIDO2).
class PasskeyAuthFailure extends Failure {
  const PasskeyAuthFailure([super.message = 'Fallo en la verificación criptográfica de la llave de acceso.']);
}
