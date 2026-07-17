/// @file lib/features/subscription/domain/entities/user_subscription.dart
/// @description Entidad de dominio para el estado y vigencia de la membresía del cliente en GymPro.

import 'package:equatable/equatable.dart';

class UserSubscription extends Equatable {
  final String status;       // 'active', 'free_pass', 'past_due', 'canceled', 'none'
  final DateTime validoHasta;
  final String planName;     // e.g. 'GymPro VIP AI Coach'
  final String metodoPago;   // 'stripe' | 'cash'

  const UserSubscription({
    required this.status,
    required this.validoHasta,
    required this.planName,
    required this.metodoPago,
  });

  /// Determina si el usuario tiene una membresía válida y al día para ingresar al gym y usar los módulos IA.
  bool get isAccessValid {
    final now = DateTime.now();
    return (status == 'active' || status == 'free_pass') && validoHasta.isAfter(now);
  }

  /// Mensaje legible en UI sobre el estatus actual.
  String get statusDisplayLabel {
    if (isAccessValid) return 'Membresía Activa';
    if (status == 'past_due') return 'Pago Pendiente / Vencido';
    if (status == 'canceled') return 'Suscripción Cancelada';
    return 'Sin Membresía Activa';
  }

  @override
  List<Object?> get props => [status, validoHasta, planName, metodoPago];
}
