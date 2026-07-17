/// @file lib/core/config/app_config.dart
/// @description Configuración central de red y URLs de microservicios de GymPro.

class AppConfig {
  AppConfig._();

  /// URL Base del microservicio de autenticación (auth-service) desplegado en Railway
  static const String authServiceBaseUrl = 'https://auth-service.up.railway.app/api/v1/auth';

  /// URL Base de servicios adicionales (pagos, accesos, fitness, IA)
  static const String accessServiceBaseUrl = 'https://access-service.up.railway.app/api/v1/access';
  static const String paymentServiceBaseUrl = 'https://payment-service.up.railway.app/api/v1/payments';
  static const String fitnessServiceBaseUrl = 'https://fitness-service.up.railway.app/api/v1';
  static const String aiServiceBaseUrl = 'https://ai-service.up.railway.app/api/v1';

  /// Timeouts de red para el cliente HTTP Dio
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Clave de almacenamiento en flutter_secure_storage para tokens
  static const String keyAccessToken = 'gympro_access_token';
  static const String keyRefreshToken = 'gympro_refresh_token';
  static const String keyUserData = 'gympro_user_json';
}
