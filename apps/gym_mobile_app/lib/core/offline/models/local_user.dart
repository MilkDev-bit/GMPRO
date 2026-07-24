/// @file lib/core/offline/models/local_user.dart
/// @description Caché local del perfil del usuario (Single Source of Truth para la UI).
/// Se actualiza desde el backend en background; la UI SIEMPRE lee de aquí.
///
/// Regenerar tras cambios:  dart run build_runner build --delete-conflicting-outputs

import 'package:isar/isar.dart';

part 'local_user.g.dart';

@collection
class LocalUser {
  Id id = Isar.autoIncrement;

  /// UUID del usuario en el backend. Único → upsert idempotente al sincronizar.
  @Index(unique: true, replace: true)
  late String remoteId;

  late String nombre;
  String? apellidoPaterno;
  late String email;
  String? avatarUrl;

  // Datos físicos (para cálculos offline: 1RM, macros…).
  double? pesoKg;
  double? estaturaCm;

  /// Marca de la última sincronización con el backend (para políticas de refresco).
  DateTime updatedAt = DateTime.now();

  LocalUser();
}
