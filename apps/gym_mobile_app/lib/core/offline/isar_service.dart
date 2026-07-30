/// @file lib/core/offline/isar_service.dart
/// @description Singleton que gestiona la base de datos Isar local.
///
/// Reglas respetadas:
///   • R1: sin BuildContext ni dependencias de UI.
///   • R2: Isar es la Single Source of Truth; se exponen streams (`watchAll`)
///     para que la UI reaccione a los cambios locales.

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/local_routine.dart';
import 'models/local_user.dart';
import 'models/sync_action.dart';

class IsarService {
  IsarService._();
  static final IsarService instance = IsarService._();

  Isar? _isar;

  /// Acceso directo (asume `init()` ya ejecutado en el arranque).
  Isar get db {
    final isar = _isar;
    if (isar == null) {
      throw StateError('IsarService.init() no fue llamado antes de usar db.');
    }
    return isar;
  }

  bool get isReady => _isar != null;

  /// Abre la base de datos con TODOS los esquemas. Idempotente.
  /// Los *Schema los genera build_runner (dart run build_runner build).
  Future<Isar> init() async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [LocalUserSchema, LocalRoutineSchema, SyncActionSchema],
      directory: dir.path,
      name: 'gympro',
    );
    return _isar!;
  }

  // ── CRUD genérico ──────────────────────────────────────────────────────────
  // `db.collection<T>()` resuelve la colección tipada (T debe ser @collection).

  Future<int> put<T>(T object) =>
      db.writeTxn(() => db.collection<T>().put(object));

  Future<void> putAll<T>(List<T> objects) =>
      db.writeTxn(() => db.collection<T>().putAll(objects));

  Future<List<T>> getAll<T>() => db.collection<T>().where().findAll();

  Future<T?> getById<T>(int id) => db.collection<T>().get(id);

  Future<bool> deleteById<T>(int id) =>
      db.writeTxn(() => db.collection<T>().delete(id));

  Future<void> clear<T>() => db.writeTxn(() => db.collection<T>().clear());

  /// Stream reactivo de TODA una colección (R2: la UI se suscribe a esto).
  /// `fireImmediately: true` emite el estado actual al suscribirse.
  Stream<List<T>> watchAll<T>() =>
      db.collection<T>().where().watch(fireImmediately: true);

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
