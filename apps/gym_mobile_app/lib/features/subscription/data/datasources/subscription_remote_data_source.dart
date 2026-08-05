/// @file lib/features/subscription/data/datasources/subscription_remote_data_source.dart
/// @description Fuente de datos remota para consultar al microservicio el estado de membresía.

import 'package:dio/dio.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_subscription_model.dart';

abstract class SubscriptionRemoteDataSource {
  Future<UserSubscriptionModel> fetchSubscriptionStatus();
}

class SubscriptionRemoteDataSourceImpl implements SubscriptionRemoteDataSource {
  final ApiClient _apiClient;

  SubscriptionRemoteDataSourceImpl(this._apiClient);

  @override
  Future<UserSubscriptionModel> fetchSubscriptionStatus() async {
    try {
      // Ruta REAL del backend: GET /api/v1/subscriptions/active (plural).
      // Normalizamos el base porque PAYMENT_SERVICE_URL puede traer '/payments'
      // (antes pedía '/payments/subscription/my-status' → 404 → siempre "vencido").
      final base = AppConfig.paymentServiceBaseUrl.replaceFirst(RegExp(r'/payments/?$'), '');
      final response = await _apiClient.get(
        '$base/subscriptions/active',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return UserSubscriptionModel.fromJson(response.data);
      } else if (response.statusCode == 402 || response.statusCode == 403) {
        // 402 Payment Required: devolvemos modelo explícito en estado vencido
        return UserSubscriptionModel(
          status: 'past_due',
          validoHasta: DateTime.now().subtract(const Duration(days: 1)),
          planName: 'Membresía GymPro Vencida',
          metodoPago: 'none',
        );
      } else if (response.statusCode == 404) {
        // No tiene membresía creada
        return UserSubscriptionModel(
          status: 'canceled',
          validoHasta: DateTime.now().subtract(const Duration(days: 10)),
          planName: 'Sin Membresía',
          metodoPago: 'none',
        );
      } else {
        throw ServerException('Error al consultar membresía (${response.statusCode})');
      }
    } on DioException catch (e) {
      // Manejo de offline o error de red: devolvemos último estado o lanzamos excepción
      if (e.response?.statusCode == 402) {
        return UserSubscriptionModel(
          status: 'past_due',
          validoHasta: DateTime.now().subtract(const Duration(days: 1)),
          planName: 'Membresía Vencida / Pago Requerido',
          metodoPago: 'stripe',
        );
      }
      throw ServerException('No fue posible contactar el microservicio de pagos: ${e.message}');
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Error procesando respuesta de membresía: $e');
    }
  }
}
