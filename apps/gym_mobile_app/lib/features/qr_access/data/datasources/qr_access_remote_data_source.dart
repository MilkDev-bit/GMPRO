/// @file lib/features/qr_access/data/datasources/qr_access_remote_data_source.dart
/// @description Fuente de datos remota conectando con el endpoint /generate-qr en access-service.

import 'package:dio/dio.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/access_qr_token_model.dart';

abstract class QrAccessRemoteDataSource {
  Future<AccessQrTokenModel> fetchNewDynamicQr();
}

class QrAccessRemoteDataSourceImpl implements QrAccessRemoteDataSource {
  final ApiClient _apiClient;

  QrAccessRemoteDataSourceImpl(this._apiClient);

  @override
  Future<AccessQrTokenModel> fetchNewDynamicQr() async {
    try {
      final response = await _apiClient.post(
        '${AppConfig.accessServiceBaseUrl}/generate-qr',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return AccessQrTokenModel.fromJson(response.data);
      } else if (response.statusCode == 402) {
        // 402 Payment Required: Membresía vencida o con adeudos
        throw const AuthException(
          'Pago Requerido: La membresía se encuentra vencida o inactiva.',
          statusCode: 402,
        );
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        throw const AuthException(
          'Acceso denegado o sesión expirada.',
          statusCode: 403,
        );
      } else {
        throw ServerException('No fue posible generar el QR de acceso (${response.statusCode})');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw const AuthException(
          'Pago Requerido: La membresía se encuentra vencida o inactiva.',
          statusCode: 402,
        );
      }
      throw ServerException('Error de red al conectar con access-service: ${e.message}');
    } catch (e) {
      if (e is AuthException || e is ServerException) rethrow;
      throw ServerException('Error inesperado al solicitar token biométrico: $e');
    }
  }
}
