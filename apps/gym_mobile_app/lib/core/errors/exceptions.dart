/// @file lib/core/errors/exceptions.dart
/// @description Excepciones lanzadas en la capa de datos (Data Sources) antes de transformarse en Failures.

/// Excepción lanzada cuando el usuario cancela explícitamente el modal nativo de Apple o Google.
class UserCancelledException implements Exception {
  final String message;
  const UserCancelledException([this.message = 'El usuario canceló el inicio de sesión.']);

  @override
  String toString() => 'UserCancelledException: $message';
}

/// Excepción cuando el backend (auth-service) rechaza la autenticación (401, 403, 422).
class AuthException implements Exception {
  final String message;
  final int? statusCode;
  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException($statusCode): $message';
}

/// Excepción cuando falla la red o el servidor (500+).
class ServerException implements Exception {
  final String message;
  const ServerException(this.message);

  @override
  String toString() => 'ServerException: $message';
}

/// Excepción cuando la biometría o el chip de seguridad no es accesible.
class BiometricNotAvailableException implements Exception {
  final String message;
  const BiometricNotAvailableException([this.message = 'Biometría o hardware no compatible.']);

  @override
  String toString() => 'BiometricNotAvailableException: $message';
}

/// Excepción durante la verificación o registro criptográfico con Passkey.
class PasskeyException implements Exception {
  final String message;
  const PasskeyException(this.message);

  @override
  String toString() => 'PasskeyException: $message';
}
