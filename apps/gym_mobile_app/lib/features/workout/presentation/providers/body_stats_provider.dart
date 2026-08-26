/// @file lib/features/workout/presentation/providers/body_stats_provider.dart
/// @description Estado de las estadísticas corporales: serie de peso (con meta) y
/// heatmap de actividad. Local-first sobre los stores de la app.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/body_weight_store.dart';
import '../../domain/body/activity_heatmap.dart';
import '../../domain/body/body_weight.dart';
import 'guided_workout_provider.dart' show activityStoreProvider;

// ── Peso corporal ─────────────────────────────────────────────────────────────
final bodyWeightStoreProvider = Provider<BodyWeightStore>((ref) {
  return SharedPrefsBodyWeightStore();
});

class BodyWeightNotifier extends StateNotifier<AsyncValue<WeightSeries>> {
  BodyWeightNotifier(this._store) : super(const AsyncValue.loading()) {
    _load();
  }

  final BodyWeightStore _store;

  Future<void> _load() async {
    try {
      state = AsyncValue.data(await _store.load());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Registra (o reemplaza) el peso de un día y persiste.
  Future<void> logWeight(double kg, {DateTime? date}) async {
    final current = state.value ?? const WeightSeries([]);
    final updated = current.upsert(WeightEntry(date: date ?? DateTime.now(), kg: kg));
    state = AsyncValue.data(updated);
    await _store.saveSeries(updated);
  }

  /// Fija (o quita, con null) la meta de peso.
  Future<void> setGoal(double? kg) async {
    final current = state.value ?? const WeightSeries([]);
    final updated = current.withGoal(kg);
    state = AsyncValue.data(updated);
    await _store.saveSeries(updated);
  }
}

final bodyWeightProvider =
    StateNotifierProvider<BodyWeightNotifier, AsyncValue<WeightSeries>>((ref) {
  return BodyWeightNotifier(ref.watch(bodyWeightStoreProvider));
});

// ── Heatmap de actividad (último año) ─────────────────────────────────────────
// Reutiliza el mismo ActivityStore que alimenta el runner guiado al finalizar.
final activityHeatmapProvider = FutureProvider<Heatmap>((ref) async {
  final records = await ref.watch(activityStoreProvider).load();
  return buildYearHeatmap(records);
});
