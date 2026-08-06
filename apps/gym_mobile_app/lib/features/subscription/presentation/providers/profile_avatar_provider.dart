/// @file lib/features/subscription/presentation/providers/profile_avatar_provider.dart
/// @description Foto de perfil personalizable del socio. La imagen se elige desde
/// la galería, se copia al directorio de documentos de la app y su ruta se
/// persiste en el almacenamiento seguro. Es local al dispositivo (no se sube al
/// backend), consistente con los demás perfiles locales.

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class ProfileAvatarNotifier extends StateNotifier<String?> {
  ProfileAvatarNotifier(this._storage) : super(null) {
    _load();
  }

  final dynamic _storage; // SecureStorageService
  final ImagePicker _picker = ImagePicker();

  Future<void> _load() async {
    final path = await _storage.getAvatarPath();
    // Si el archivo ya no existe (p.ej. limpieza del SO), lo ignoramos.
    if (path != null && await File(path).exists()) {
      if (mounted) state = path;
    }
  }

  /// Abre la galería, copia la imagen elegida al directorio de la app y persiste
  /// su ruta. Devuelve true si se actualizó la foto.
  Future<bool> pickFromGallery() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return false;

      final dir = await getApplicationDocumentsDirectory();
      // Nombre único (timestamp) para invalidar la caché de imágenes de Flutter.
      final ext = p.extension(picked.path).isNotEmpty ? p.extension(picked.path) : '.jpg';
      final dest = p.join(dir.path, 'profile_avatar_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(picked.path).copy(dest);

      // Borra la foto anterior para no acumular archivos.
      final previous = state;
      await _storage.saveAvatarPath(dest);
      if (mounted) state = dest;
      if (previous != null && previous != dest) {
        try { await File(previous).delete(); } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ [ProfileAvatar] No se pudo elegir la foto: $e');
      return false;
    }
  }

  /// Quita la foto personalizada y vuelve al avatar por defecto.
  Future<void> removeAvatar() async {
    final previous = state;
    await _storage.saveAvatarPath(null);
    if (mounted) state = null;
    if (previous != null) {
      try { await File(previous).delete(); } catch (_) {}
    }
  }
}

final profileAvatarProvider =
    StateNotifierProvider<ProfileAvatarNotifier, String?>((ref) {
  return ProfileAvatarNotifier(ref.watch(secureStorageProvider));
});
