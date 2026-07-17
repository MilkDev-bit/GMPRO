/// @file lib/features/payment/data/datasources/payment_remote_data_source.dart
/// @description Fuente de datos remota para contactar con /api/v1/payments/create-checkout-session.

import 'package:dio/dio.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';

abstract class PaymentRemoteDataSource {
  Future<String> createCheckoutSession({
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  });
}

class PaymentRemoteDataSourceImpl implements PaymentRemoteDataSource {
  final ApiClient _apiClient;

  PaymentRemoteDataSourceImpl(this._apiClient);

  @override
  Future<String> createCheckoutSession({
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      final response = await _apiClient.post(
        '${AppConfig.paymentServiceBaseUrl}/payments/create-checkout-session',
        data: {
          'priceId': priceId,
          if (successUrl != null) 'successUrl': successUrl,
          if (cancelUrl != null) 'cancelUrl': cancelUrl,
        },
      );

      if (response.statusCode == 200 && response.data?['data']?['url'] != null) {
        return response.data['data']['url'].toString();
      } else {
        throw ServerException('No se recibió la URL de sesión de pago Stripe.');
      }
    } on DioException catch (e) {
      throw ServerException('Error al contactar con el portal de pagos Stripe: ${e.message}');
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Error procesando solicitud de pago: $e');
    }
  }
}
