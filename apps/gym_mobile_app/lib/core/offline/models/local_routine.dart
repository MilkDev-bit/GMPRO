/// @file lib/core/offline/models/local_routine.dart
/// @description Caché local de la rutina del día y del historial de sesiones.
///
/// Regenerar tras cambios:  dart run build_runner build --delete-conflicting-outputs

import 'package:isar/isar.dart';

part 'local_routine.g.dart';

@collection
class LocalRoutine {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String remoteId;

  @Index()
  late String usuarioId;

  late String nombre;
  String? nivel;

  /// Ejercicios serializados como JSON (Isar no anida colecciones arbitrarias;
  /// para un catálogo dinámico, JSON es la opción pragmática y portable).
  late String ejerciciosJson;

  /// true = la rutina asignada para HOY (la UI la resuelve sin red).
  @Index()
  bool esDelDia = false;

  /// Historial: si está completada y cuándo (se llena también offline).
  bool completada = false;
  DateTime? completadaEn;

  DateTime updatedAt = DateTime.now();

  LocalRoutine();
}
