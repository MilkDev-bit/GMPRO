/// @file lib/features/auth/data/models/oauth_credential_model.dart
/// @description Modelo de datos DTO enviado al backend (/api/v1/auth/oauth-login) con las credenciales nativas del SO.

class OAuthCredentialModel {
  final String provider; // 'google' | 'apple'
  final String idToken;
  final String email;
  final String? nombre;
  final String? apellidoPaterno;

  const OAuthCredentialModel({
    required this.provider,
    required this.idToken,
    required this.email,
    this.nombre,
    this.apellidoPaterno,
  });

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'idToken': idToken,
      'email': email,
      'nombre': nombre ?? 'Socio',
      'apellidoPaterno': apellidoPaterno ?? provider.toUpperCase(),
    };
  }
}
