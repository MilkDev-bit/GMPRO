/// @file lib/features/subscription/data/models/user_subscription_model.dart
/// @description Modelo DTO que parsea la respuesta JSON del microservicio de pagos/usuarios.

import '../../domain/entities/user_subscription.dart';

class UserSubscriptionModel extends UserSubscription {
  const UserSubscriptionModel({
    required super.status,
    required super.validoHasta,
    required super.planName,
    required super.metodoPago,
  });

  factory UserSubscriptionModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    
    // Parseo seguro de fecha de vencimiento (ISO8601 o timestamp)
    DateTime expirationDate;
    final dateRaw = data['valido_hasta'] ?? data['validoHasta'];
    if (dateRaw != null) {
      expirationDate = DateTime.tryParse(dateRaw.toString()) ?? DateTime.now().add(const Duration(days: 30));
    } else {
      expirationDate = DateTime.now().add(const Duration(days: 30));
    }

    return UserSubscriptionModel(
      status: (data['estado'] ?? data['status'] ?? 'active').toString().toLowerCase(),
      validoHasta: expirationDate,
      planName: data['plan_name']?.toString() ?? 'GymPro VIP AI Coach',
      metodoPago: data['metodo_pago']?.toString() ?? 'stripe',
    );
  }
}
