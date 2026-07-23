/// @file lib/core/security/security_guard.dart
/// @description RASP con freerasp (Talsec). Detecta entornos comprometidos y
/// aplica una política HÍBRIDA:
///   • Pasivas (root/jailbreak, emulador, debugger, tienda no oficial) →
///     MODO DEGRADADO: advertencia no bloqueante + `isCompromised = true`
///     (los flujos sensibles —pagos/biometría— abortan al leer ese flag).
///   • Activas (hooks/Frida, tampering/repackaging) → CIERRE INMEDIATO tras
///     registrar el evento crítico.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freerasp/freerasp.dart';

import '../logging/app_logger.dart';

class SecurityGuard extends ChangeNotifier {
  SecurityGuard._();
  static final SecurityGuard instance = SecurityGuard._();

  final Set<String> _threats = <String>{};
  bool _isCompromised = false;

  /// True si se detectó CUALQUIER amenaza (pasiva o activa). Los flujos
  /// sensibles DEBEN abortar si es true (bloqueo duro en pagos/biometría).
  bool get isCompromised => _isCompromised;

  /// Amenazas detectadas (para telemetría/depuración).
  Set<String> get threats => Set<String>.unmodifiable(_threats);

  /// Advertencia no bloqueante (Toast/Snackbar). La inyecta `main` para no
  /// acoplar el guard con la capa de UI.
  void Function(String message)? _onWarning;

  /// Inicializa Talsec/freerasp y ata los listeners. Llamar UNA vez al arranque.
  Future<void> initialize({void Function(String message)? onWarning}) async {
    _onWarning = onWarning;

    final callback = ThreatCallback(
      // ── PASIVAS → modo degradado ────────────────────────────────────────
      onPrivilegedAccess: () => _passive('root_jailbreak'),
      onSimulator: () => _passive('emulador'),
      onDebug: () => _passive('debugger'),
      onUnofficialStore: () => _passive('tienda_no_oficial'),
      onDeviceBinding: () => _passive('device_binding'),
      // ── ACTIVAS → cierre inmediato ──────────────────────────────────────
      onHooks: () => _active('hooks_frida'),
      onAppIntegrity: () => _active('tampering_repackaging'),
    );

    Talsec.instance.attachListener(callback);
    await Talsec.instance.start(_buildConfig());
    AppLogger.d('RASP (freerasp) inicializado', tag: 'RASP');
  }

  /// Config de Talsec. ⚠ Los identificadores y hashes DEBEN rellenarse con los
  /// valores reales de firma/bundle antes de release, o la atestación fallará.
  TalsecConfig _buildConfig() => TalsecConfig(
        androidConfig: AndroidConfig(
          packageName: 'com.gympro.app', // ⚠ REEMPLAZAR con el applicationId real
          signingCertHashes: const [
            // SHA-256 (base64) del certificado de firma de RELEASE. Obtener con:
            //   keytool -list -v -keystore <release.jks> -alias <alias>
            //   (toma el SHA256 y conviértelo de hex a base64). ⚠ REEMPLAZAR.
            'REEMPLAZAR_SHA256_BASE64_DEL_CERT_DE_FIRMA=',
          ],
          supportedStores: const ['com.android.vending'],
        ),
        iosConfig: IOSConfig(
          bundleIds: const ['com.gympro.app'], // ⚠ REEMPLAZAR
          teamId: 'REEMPLAZAR_TEAMID',
        ),
        watcherMail: 'security@gympro-ai.com',
        // En debug Talsec relaja checks (p.ej. debugger) para no romper el
        // desarrollo; en release aplica todo con severidad de producción.
        isProd: kReleaseMode,
      );

  /// PASIVA: marca estado, avisa (no bloqueante) y notifica a la UI. Idempotente
  /// por tipo de amenaza (no spamea el toast si se repite el mismo evento).
  void _passive(String threat) {
    final isNew = _threats.add(threat);
    _isCompromised = true;
    if (isNew) {
      AppLogger.w('Amenaza pasiva detectada: $threat → modo degradado', tag: 'RASP');
      _onWarning?.call(
        'Dispositivo comprometido detectado. Funciones sensibles deshabilitadas.',
      );
      notifyListeners();
    }
  }

  /// ACTIVA (tampering/hooks): log CRÍTICO + cierre inmediato de la app.
  void _active(String threat) {
    _threats.add(threat);
    _isCompromised = true;
    AppLogger.e('AMENAZA ACTIVA ($threat): manipulación en runtime → cierre forzado',
        tag: 'RASP');
    notifyListeners();
    // Cierre inmediato. Nota: en iOS SystemNavigator.pop() minimiza pero puede
    // no terminar el proceso (Apple lo desaconseja); el registro crítico previo
    // queda para el SIEM/crash reporter aunque el cierre no sea "duro".
    SystemNavigator.pop();
  }
}

/// Provider Riverpod para observar el estado desde la UI y los flujos sensibles.
///   final compromised = ref.watch(securityGuardProvider).isCompromised;
final securityGuardProvider = ChangeNotifierProvider<SecurityGuard>(
  (ref) => SecurityGuard.instance,
);
