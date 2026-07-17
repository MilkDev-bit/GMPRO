/// @file lib/features/qr_access/domain/entities/access_qr_token.dart
/// @description Entidad de dominio que encapsula el token criptográfico AES-256 de 30 segundos.

import 'package:equatable/equatable.dart';

class AccessQrToken extends Equatable {
  final String token;        // String encriptado AES-256 devuelto por /generate-qr
  final DateTime expiresAt;  // Marca de tiempo exacta de expiración (now + 30s)
  final int refreshInterval; // Intervalo exacto de refresco en segundos (30s)

  const AccessQrToken({
    required this.token,
    required this.expiresAt,
    this.refreshInterval = 30,
  });

  /// Determina si este token en particular aún es válido o ya caducó en milisegundos.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  List<Object?> get props => [token, expiresAt, refreshInterval];
}
