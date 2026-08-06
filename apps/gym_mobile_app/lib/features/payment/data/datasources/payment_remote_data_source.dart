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
      // El base remoto puede venir CON o SIN '/payments' según la env
      // (PAYMENT_SERVICE_URL); normalizamos para NO duplicarlo, que producía
      // '/api/v1/payments/payments/create-checkout-session' → 404.
      final base = AppConfig.paymentServiceBaseUrl.replaceFirst(RegExp(r'/payments/?$'), '');
      final response = await _apiClient.post(
        '$base/payments/create-checkout-session',
        data: {
          // `priceId` transporta ahora el PLAN ('mensual'/'trimestral'); el
          // backend resuelve el Stripe Price ID real desde su env (nunca se
          // confía en un precio dictado por el cliente).
          'plan': priceId,
          if (successUrl != null) 'successUrl': successUrl,
          if (cancelUrl != null) 'cancelUrl': cancelUrl,
        },
      );

      if (response.statusCode == 200 && response.data?['data']?['url'] != null) {
        return response.data['data']['url'].toString();
      } else {
        throw const ServerException('No se recibió la URL de sesión de pago Stripe.');
      }
    } on DioException catch (e) {
      // Mensaje AMIGABLE mapeado por status; NO volcamos la excepción cruda de
      // Dio en pantalla (antes salía un bloque rojo enorme e ilegible).
      final sc = e.response?.statusCode ?? 0;
      // Intentar extraer el mensaje de error del servidor si lo envía
      final serverMsg = e.response?.data is Map
          ? (e.response!.data['error'] as String?)
          : null;
      final msg = switch (sc) {
        401 => 'Tu sesión ha expirado. Cierra sesión y vuelve a iniciar.',
        403 => 'No tienes permisos para esta operación.',
        404 => 'No encontramos el plan de pago. Contacta a soporte.',
        422 => serverMsg ?? 'Datos de pago inválidos. Inténtalo de nuevo.',
        >= 500 => 'El servidor de pagos tuvo un problema. Inténtalo en unos minutos.',
        _ => 'No pudimos iniciar el pago. Revisa tu conexión e inténtalo de nuevo.',
        _ => 'No pudimos iniciar el pago. Revisa tu conexión e inténtalo de nuevo.',
      };
      throw ServerException(msg);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Error procesando solicitud de pago: $e');
    }
  }
}
