/// @file lib/features/auth/domain/entities/auth_user.dart
/// @description Entidad pura de dominio para el usuario autenticado en GymPro.

import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  final String id;
  final String email;
  final String nombre;
  final String apellidoPaterno;
  final String rol;
  final bool emailVerificado;
  final String accessToken;

  const AuthUser({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellidoPaterno,
    required this.rol,
    required this.emailVerificado,
    required this.accessToken,
  });

  @override
  List<Object?> get props => [
        id,
        email,
        nombre,
        apellidoPaterno,
        rol,
        emailVerificado,
        accessToken,
      ];
}
