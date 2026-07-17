/// @file lib/features/auth/data/models/auth_response_model.dart
/// @description Modelo de respuesta del servidor convirtiendo el JSON de GymPro a la entidad AuthUser.

import '../../domain/entities/auth_user.dart';

class AuthResponseModel extends AuthUser {
  final String refreshToken;
  final int expiresIn;

  const AuthResponseModel({
    required super.id,
    required super.email,
    required super.nombre,
    required super.apellidoPaterno,
    required super.rol,
    required super.emailVerificado,
    required super.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final userJson = data['user'] ?? data;

    return AuthResponseModel(
      id: userJson['id']?.toString() ?? '',
      email: userJson['email']?.toString() ?? '',
      nombre: userJson['nombre']?.toString() ?? 'Socio',
      apellidoPaterno: userJson['apellido_paterno']?.toString() ?? 'GymPro',
      rol: userJson['rol']?.toString() ?? 'miembro',
      emailVerificado: userJson['email_verificado'] == true,
      accessToken: data['accessToken']?.toString() ?? '',
      refreshToken: data['refreshToken']?.toString() ?? '',
      expiresIn: int.tryParse(data['expiresIn']?.toString() ?? '900') ?? 900,
    );
  }

  Map<String, dynamic> toUserDataMap() {
    return {
      'id': id,
      'email': email,
      'nombre': nombre,
      'apellido_paterno': apellidoPaterno,
      'rol': rol,
      'email_verificado': emailVerificado,
    };
  }
}
