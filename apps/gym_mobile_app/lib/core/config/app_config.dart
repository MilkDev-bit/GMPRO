/// @file lib/core/config/app_config.dart
/// @description Configuración central de red y URLs de microservicios de GymPro.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

class AppConfig {
  AppConfig._();

  // ───────────────────────────────────────────────────────────────────
  // Selección de entorno
  //
  // Antes las URLs apuntaban SIEMPRE a Railway, así que la app nunca
  // hablaba con el backend local aunque estuviera levantado con Docker.
  //
  // Ahora en debug se usa el backend local por defecto. Para forzar
  // producción desde debug:
  //   flutter run --dart-define=USE_REMOTE_BACKEND=true
  // ───────────────────────────────────────────────────────────────────
  static const bool _forceRemote =
      bool.fromEnvironment('USE_REMOTE_BACKEND', defaultValue: false);

  static bool get useLocalBackend => kDebugMode && !_forceRemote;

  /// Host del backend local visto DESDE el dispositivo.
  ///
  /// ⚠ El emulador de Android corre en su propia VM: `localhost` es el
  /// propio emulador, no tu máquina. La puerta de enlace al host es
  /// 10.0.2.2. En el simulador de iOS y en web sí vale localhost.
  ///
  /// Para un dispositivo FÍSICO ninguna de las dos sirve: hay que usar
  /// la IP de tu máquina en la LAN.
  ///   flutter run --dart-define=LOCAL_HOST=192.168.1.42
  static const String _hostOverride =
      String.fromEnvironment('LOCAL_HOST', defaultValue: '');

  static String get _localHost {
    if (_hostOverride.isNotEmpty) return _hostOverride;
    if (kIsWeb) return 'localhost';
    return Platform.isAndroid ? '10.0.2.2' : 'localhost';
  }

  // Puertos publicados en docker-compose.yml.
  // ⚠ access=3002 y payment=3003 (no al revés): es fácil cruzarlos y el
  // síntoma es confuso — el servicio responde, pero con 404 en todas las
  // rutas porque los prefijos no coinciden.
  static const int _authPort = 3001;
  static const int _accessPort = 3002;
  static const int _paymentPort = 3003;
  static const int _fitnessPort = 3004;
  static const int _aiPort = 3005;

  static String _local(int port) => 'http://$_localHost:$port';

  // ───────────────────────────────────────────────────────────────────
  // URLs de los microservicios
  // ───────────────────────────────────────────────────────────────────
  static String get authServiceBaseUrl => useLocalBackend
      ? '${_local(_authPort)}/api/v1/auth'
      : 'https://auth-service.up.railway.app/api/v1/auth';

  static String get accessServiceBaseUrl => useLocalBackend
      ? '${_local(_accessPort)}/api/v1/access'
      : 'https://access-service.up.railway.app/api/v1/access';

  static String get paymentServiceBaseUrl => useLocalBackend
      ? '${_local(_paymentPort)}/api/v1/payments'
      : 'https://payment-service.up.railway.app/api/v1/payments';

  static String get fitnessServiceBaseUrl => useLocalBackend
      ? '${_local(_fitnessPort)}/api/v1'
      : 'https://fitness-service.up.railway.app/api/v1';

  static String get aiServiceBaseUrl => useLocalBackend
      ? '${_local(_aiPort)}/api/v1'
      : 'https://ai-service.up.railway.app/api/v1';

  /// Resumen para loguear al arrancar: evita el clásico "¿por qué no
  /// veo mis cambios?" cuando la app apunta al entorno equivocado.
  static Map<String, String> get environmentSummary => {
        'modo': useLocalBackend ? 'LOCAL' : 'REMOTO (Railway)',
        'host': useLocalBackend ? _localHost : 'railway.app',
        'ai': aiServiceBaseUrl,
      };

  /// Timeouts de red para el cliente HTTP Dio
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// ── Supabase (Realtime de vigencia de membresía) ─────────────────────────
  /// Se inyectan por --dart-define en CI/CD (no hardcodear la anon key en repos).
  /// El esquema payment_service_db debe estar publicado en `supabase_realtime`
  /// y con una RLS que permita al socio leer SOLO su propia fila de suscripciones.
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Indica si el Realtime está configurado (evita inicializar canales vacíos).
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Clave de almacenamiento en flutter_secure_storage para tokens
  static const String keyAccessToken = 'gympro_access_token';
  static const String keyRefreshToken = 'gympro_refresh_token';
  static const String keyUserData = 'gympro_user_json';

  /// Conjunto de HOSTS propios del backend (derivado de las base URLs).
  /// Úsalo para decidir a quién se le adjunta el Bearer token: NUNCA se debe
  /// enviar el JWT a un host que no esté aquí (evita token leakage a terceros
  /// —analytics, CDN, imágenes— si comparten la instancia de Dio).
  static Set<String> get backendHosts => <String>{
        Uri.parse(authServiceBaseUrl).host,
        Uri.parse(accessServiceBaseUrl).host,
        Uri.parse(paymentServiceBaseUrl).host,
        Uri.parse(fitnessServiceBaseUrl).host,
        Uri.parse(aiServiceBaseUrl).host,
      };

  /// True si el host de destino pertenece a nuestro backend.
  static bool isBackendHost(String host) => backendHosts.contains(host);

  // ───────────────────────────────────────────────────────────────────
  // Certificate Pinning (SPKI)
  // ───────────────────────────────────────────────────────────────────

  /// KILL-SWITCH del SSL pinning. Default `true` (pinning activo). Ante una
  /// rotación catastrófica de claves (se pierden AMBOS pines), se apaga por
  /// build-time para que la app vuelva al TLS estándar del SO sin dejar a los
  /// usuarios fuera:
  ///   flutter build ... --dart-define=SSL_PINNING_ENABLED=false
  ///
  /// En debug/local el pinning se desactiva solo: el backend local es http y
  /// no tiene certificado que pinnear.
  static bool get isSSLPinningEnabled {
    const forced = bool.fromEnvironment('SSL_PINNING_ENABLED', defaultValue: true);
    return forced && !useLocalBackend;
  }

  /// Pines SPKI = SHA-256(SubjectPublicKeyInfo) en base64. Se acepta la conexión
  /// si el cert del servidor coincide con CUALQUIERA (multi-pin).
  ///
  /// NOTA de diseño: `badCertificateCallback` de dart:io solo expone el cert
  /// LEAF (no la cadena), así que ambos pines son a nivel LEAF:
  ///   • Pin A = clave pública actual (leaf en producción).
  ///   • Pin B = clave de RESPALDO pre-generada offline (para rotación segura).
  /// Pinnear la CA intermedia NO es posible aquí; el backup-key es la práctica
  /// recomendada por OWASP en su lugar.
  ///
  /// Generar el hash real de cada host:
  ///   openssl s_client -connect <host>:443 -servername <host> < /dev/null 2>/dev/null \
  ///     | openssl x509 -pubkey -noout \
  ///     | openssl pkey -pubin -outform der \
  ///     | openssl dgst -sha256 -binary | openssl enc -base64
  static const Set<String> certificatePins = <String>{
    // Pin A — clave pública ACTUAL (leaf). ⚠ REEMPLAZAR con el hash real.
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    // Pin B — clave de RESPALDO pre-generada (backup). ⚠ REEMPLAZAR.
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
  };
}
