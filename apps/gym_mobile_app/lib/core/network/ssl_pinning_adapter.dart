/// @file lib/core/network/ssl_pinning_adapter.dart
/// @description Certificate Pinning por SPKI para Dio (nativo). Fuerza la
/// validación de pines en TODAS las conexiones y soporta kill-switch remoto.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';

class SSLPinningAdapter {
  SSLPinningAdapter._();

  /// Construye el adapter de Dio con pinning SPKI. Enchúfalo con
  /// `dio.httpClientAdapter = SSLPinningAdapter.build();`
  static IOHttpClientAdapter build() {
    return IOHttpClientAdapter(
      createHttpClient: () {
        // ── KILL-SWITCH / PINES SIN CONFIGURAR → TLS estándar del SO ────────
        // Dos vías de fail-open que evitan dejar a los usuarios sin conexión:
        //   1. Kill-switch remoto (build-time) o backend local (http).
        //   2. Pines aún en placeholder (hasConfiguredPins == false): así, si se
        //      despliega sin haber puesto los hashes reales, la app NO se brickea.
        //      El pinning (fail-closed) se activa solo al colocar un pin real.
        if (!AppConfig.isSSLPinningEnabled || !AppConfig.hasConfiguredPins) {
          AppLogger.w(
            AppConfig.hasConfiguredPins
                ? 'SSL pinning DESACTIVADO (kill-switch/local). TLS del SO.'
                : 'SSL pinning INACTIVO: pines SPKI sin configurar (placeholder). '
                    'TLS del SO. ⚠ Coloca los hashes reales antes del release.',
            tag: 'SSLPinning',
          );
          return HttpClient();
        }

        // ── Pinning ON ──────────────────────────────────────────────────────
        // `withTrustedRoots: false` → NINGÚN certificado valida por sí solo, así
        // que badCertificateCallback se invoca SIEMPRE (incluso si una CA
        // corporativa/proxy está instalada en el dispositivo). Es la única forma
        // en dart:io de forzar nuestra validación en cada conexión y bloquear el
        // MITM por proxy con CA "de confianza" para el SO.
        final client =
            HttpClient(context: SecurityContext(withTrustedRoots: false));

        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          try {
            final pin = _spkiSha256Base64(cert.der);
            final accepted = AppConfig.certificatePins.contains(pin);
            if (!accepted) {
              AppLogger.w(
                'Pin SPKI NO coincide para $host:$port → conexión rechazada (posible MITM).',
                tag: 'SSLPinning',
              );
            }
            return accepted; // fail-closed: solo true si el pin coincide
          } catch (e, st) {
            // Ante cualquier fallo de parseo/validación: RECHAZAR (fail-closed).
            AppLogger.e('Error validando SPKI; conexión rechazada',
                error: e, stackTrace: st, tag: 'SSLPinning');
            return false;
          }
        };
        return client;
      },
    );
  }

  /// Calcula el pin SPKI = base64( SHA-256( SubjectPublicKeyInfo DER ) ).
  ///
  /// Extrae el SubjectPublicKeyInfo del certificado X.509 parseando su DER:
  ///   Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { ... }, ... }
  ///   tbsCertificate ::= SEQUENCE {
  ///     version [0] EXPLICIT (opcional; presente en v3),
  ///     serialNumber, signature, issuer, validity, subject,
  ///     subjectPublicKeyInfo,   ← esto es lo que hasheamos
  ///     ... }
  /// El `encodedBytes` del SPKI es su DER completo (algoritmo + clave), de modo
  /// que el hash coincide con el que produce la cadena de `openssl` documentada.
  static String _spkiSha256Base64(Uint8List certDer) {
    final parser = ASN1Parser(certDer);
    final certificate = parser.nextObject() as ASN1Sequence; // Certificate
    final tbs = certificate.elements[0] as ASN1Sequence;      // tbsCertificate

    // v3 lleva 'version' como [0] EXPLICIT (tag 0xA0) → SPKI en índice 6; v1 → 5.
    final hasVersion =
        tbs.elements.isNotEmpty && tbs.elements.first.tag == 0xA0;
    final spki = tbs.elements[hasVersion ? 6 : 5]; // SubjectPublicKeyInfo

    final digest = sha256.convert(spki.encodedBytes);
    return base64.encode(digest.bytes);
  }
}
