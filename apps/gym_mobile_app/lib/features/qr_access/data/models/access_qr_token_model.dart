/// @file lib/features/qr_access/data/models/access_qr_token_model.dart
/// @description Modelo DTO para transformar la respuesta de /api/v1/access/generate-qr a entidad de dominio.

import '../../domain/entities/access_qr_token.dart';

class AccessQrTokenModel extends AccessQrToken {
  const AccessQrTokenModel({
    required super.token,
    required super.expiresAt,
    super.refreshInterval = 30,
  });

  factory AccessQrTokenModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    
    final tokenStr = data['token']?.toString() ?? data['qr_token']?.toString() ?? '';
    final expiresInSeconds = int.tryParse(data['expires_in']?.toString() ?? '30') ?? 30;
    
    DateTime expDate;
    if (data['expires_at'] != null) {
      expDate = DateTime.tryParse(data['expires_at'].toString()) ?? DateTime.now().add(Duration(seconds: expiresInSeconds));
    } else {
      expDate = DateTime.now().add(Duration(seconds: expiresInSeconds));
    }

    return AccessQrTokenModel(
      token: tokenStr,
      expiresAt: expDate,
      refreshInterval: expiresInSeconds,
    );
  }
}
