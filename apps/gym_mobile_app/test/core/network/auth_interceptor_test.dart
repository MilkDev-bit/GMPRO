/// @file test/core/network/auth_interceptor_test.dart
/// @description Test de concurrencia del refresh SINGLE-FLIGHT: 5 peticiones
/// concurrentes que reciben 401 deben provocar UNA sola llamada a /refresh y
/// reintentarse todas con el nuevo Bearer.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:gym_mobile_app/core/config/app_config.dart';
import 'package:gym_mobile_app/core/network/auth_interceptor.dart';
import 'package:gym_mobile_app/core/storage/secure_storage_service.dart';

/// Storage en memoria: sobrescribe SOLO los métodos que usa el interceptor, de
/// modo que el FlutterSecureStorage real (platform channel) nunca se invoca.
class FakeSecureStorage extends SecureStorageService {
  String? access = 'OLD_ACCESS';
  String? refresh = 'REFRESH_1';
  int clearCount = 0;

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clearAuth() async {
    clearCount++;
    access = null;
    refresh = null;
  }
}

void main() {
  test(
    'single-flight: 5×401 concurrentes → 1 sola llamada a /refresh y 5 reintentos con el nuevo token',
    () async {
      final base = AppConfig.authServiceBaseUrl;

      // ── Dio de refresh/retry (inyectado) ──────────────────────────────────
      final refreshDio = Dio(BaseOptions(baseUrl: base));
      final refreshAdapter = DioAdapter(dio: refreshDio);

      var refreshCount = 0;
      final retryAuthHeaders = <String?>[];
      // Interceptor observador: cuenta /refresh y registra el Bearer de los retries.
      refreshDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/refresh')) refreshCount++;
          if (options.path.contains('/protected')) {
            retryAuthHeaders.add(options.headers['Authorization'] as String?);
          }
          handler.next(options);
        },
      ));

      refreshAdapter
        // /refresh responde con tokens nuevos. El DELAY garantiza que las 5
        // peticiones lleguen a onError y se encolen ANTES de que resuelva → así
        // el test es determinista respecto al single-flight.
        ..onPost(
          '/refresh',
          (server) => server.reply(
            200,
            {
              'success': true,
              'data': {'accessToken': 'NEW_ACCESS', 'refreshToken': 'REFRESH_2'},
              'error': null,
            },
            delay: const Duration(milliseconds: 200),
          ),
        )
        // Reintentos de la petición original: éxito.
        ..onGet('/protected', (server) => server.reply(200, {'ok': true}));

      // ── Dio principal: la primera vez /protected devuelve 401 ─────────────
      final mainDio = Dio(BaseOptions(baseUrl: base));
      final mainAdapter = DioAdapter(dio: mainDio);
      mainAdapter.onGet(
        '/protected',
        (server) => server.reply(401, {'error': 'token expirado'}),
      );

      final storage = FakeSecureStorage();
      mainDio.interceptors.add(
        AuthInterceptor(storage, refreshClient: refreshDio),
      );

      // ── Estrés: 5 peticiones concurrentes ─────────────────────────────────
      final responses = await Future.wait(
        List.generate(5, (_) => mainDio.get('/protected')),
      );

      // ── ASERCIONES ────────────────────────────────────────────────────────
      // 1. /refresh se llamó EXACTAMENTE una vez (el Completer bloqueó las otras 4).
      expect(refreshCount, 1, reason: 'Debe haber UNA sola llamada a /refresh');

      // 2. Las 5 peticiones se reintentaron con éxito.
      expect(responses.length, 5);
      for (final r in responses) {
        expect(r.statusCode, 200);
      }

      // 3. Los 5 reintentos usaron el NUEVO Bearer.
      expect(retryAuthHeaders.length, 5);
      for (final h in retryAuthHeaders) {
        expect(h, 'Bearer NEW_ACCESS');
      }

      // 4. El token rotado quedó guardado y NO se cerró la sesión.
      expect(storage.access, 'NEW_ACCESS');
      expect(storage.refresh, 'REFRESH_2');
      expect(storage.clearCount, 0);
    },
  );

  test(
    'fail-safe: si /refresh devuelve 401, se limpia la sesión (clearAuth) y no hay bucle',
    () async {
      final base = AppConfig.authServiceBaseUrl;

      final refreshDio = Dio(BaseOptions(baseUrl: base));
      final refreshAdapter = DioAdapter(dio: refreshDio);
      var refreshCount = 0;
      refreshDio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path.contains('/refresh')) refreshCount++;
        h.next(o);
      }));
      refreshAdapter.onPost(
        '/refresh',
        (server) => server.reply(401, {'error': 'refresh revocado'}),
      );

      final mainDio = Dio(BaseOptions(baseUrl: base));
      DioAdapter(dio: mainDio).onGet(
        '/protected',
        (server) => server.reply(401, {'error': 'expirado'}),
      );

      final storage = FakeSecureStorage();
      mainDio.interceptors.add(AuthInterceptor(storage, refreshClient: refreshDio));

      // La petición debe fallar (propaga el error) tras el fail-safe.
      await expectLater(
        mainDio.get('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(refreshCount, 1);             // se intentó refrescar una vez
      expect(storage.clearCount, 1);       // se limpió la sesión
      expect(storage.access, isNull);      // tokens borrados
    },
  );
}
