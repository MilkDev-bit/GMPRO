/// @file lib/core/services/sound_manager.dart
/// @description Gestor de feedback sensorial (Audio + Háptica) DESACOPLADO de la UI.
///
/// Reglas respetadas:
///   • R1 Desacoplamiento: Singleton sin `BuildContext`. Depende solo de
///     `audioplayers` y `flutter/services.dart` (HapticFeedback).
///   • R2 Fallback: si el asset no existe o audioplayers falla, se atrapa la
///     excepción en silencio y se ejecuta AL MENOS la vibración. La app nunca
///     se rompe por un sonido faltante.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sonidos disponibles (rutas relativas a la carpeta declarada en pubspec).
/// audioplayers usa AssetSource con ruta SIN el prefijo 'assets/'.
enum _Sfx {
  success('sounds/success.mp3'),
  click('sounds/click.mp3'),
  error('sounds/error.mp3');

  const _Sfx(this.path);
  final String path;
}

class SoundManager {
  SoundManager._();
  static final SoundManager _instance = SoundManager._();
  static SoundManager get instance => _instance;

  // Reproductor de baja latencia reutilizable para SFX cortos.
  final AudioPlayer _player = AudioPlayer(playerId: 'gympro_sfx')
    ..setReleaseMode(ReleaseMode.stop);

  bool _muted = false;

  /// Permite silenciar el audio (p. ej. desde ajustes). La háptica sigue activa.
  static void setMuted(bool muted) => _instance._muted = muted;

  // ── API pública (estática para uso ergonómico sin instanciar) ──────────────
  static Future<void> playSuccess() =>
      _instance._play(_Sfx.success, HapticFeedback.mediumImpact);

  static Future<void> playClick() =>
      _instance._play(_Sfx.click, HapticFeedback.selectionClick);

  static Future<void> playError() =>
      _instance._play(_Sfx.error, HapticFeedback.heavyImpact);

  /// Reproduce un SFX + su háptica. La háptica se dispara SIEMPRE (aunque el
  /// audio falle o esté silenciado): es el fallback garantizado (R2).
  Future<void> _play(_Sfx sfx, Future<void> Function() haptic) async {
    // 1. Háptica primero: nunca depende del audio.
    try {
      await haptic();
    } catch (_) {/* algunos dispositivos/emuladores no vibran; ignorar */}

    // 2. Audio (best-effort). Cualquier fallo (asset ausente, plugin no
    //    inicializado) se atrapa en silencio.
    if (_muted) return;
    try {
      await _player.stop(); // corta un SFX previo para no solaparlos
      await _player.play(AssetSource(sfx.path));
    } catch (e) {
      if (kDebugMode) {
        // Solo visible en debug; en release no ensucia logs (ni filtra nada).
        debugPrint('[SoundManager] audio omitido (${sfx.path}): $e');
      }
    }
  }

  /// Libera el reproductor (llamar en el dispose del root si se desea).
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
