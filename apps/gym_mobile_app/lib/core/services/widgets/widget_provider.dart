/// @file lib/core/services/widgets/widget_provider.dart
/// @description Proveedores de Riverpod para sincronizar automáticamente macros con
/// la pantalla de inicio y controlar las Live Activities desde las rutinas de ejercicio.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/nutrition/presentation/providers/nutrition_provider.dart';
import 'home_widget_service.dart';
import 'live_activity_service.dart';
import 'widget_payloads.dart';

/// Proveedor para inyectar el servicio de widgets en la pantalla de inicio (iOS/Android).
final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetServiceImpl();
});

/// Proveedor para inyectar el servicio de Live Activities (iOS 16.1+).
final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  return LiveActivityServiceImpl();
});

/// Notificador que observa el estado nutricional y empuja los cambios
/// al widget estilo Fitia de la pantalla de inicio.
class WidgetSyncNotifier extends StateNotifier<bool> {
  final Ref _ref;
  final HomeWidgetService _homeWidgetService;

  WidgetSyncNotifier(this._ref, this._homeWidgetService) : super(false) {
    _initListener();
  }

  void _initListener() {
    _ref.listen(nutritionProvider, (previous, next) {
      if (next.plan != null) {
        syncCurrentMacros();
      }
    });
  }

  /// Empuja explícitamente los datos de macros al widget nativo en segundo plano.
  Future<void> syncCurrentMacros() async {
    final state = _ref.read(nutritionProvider);
    final plan = state.plan;
    if (plan == null) return;

    final payload = MacrosWidgetPayload(
      caloriesCurrent: plan.caloriasConsumidas,
      caloriesTarget: plan.caloriasMeta,
      proteinCurrent: plan.proteinasConsumidas,
      proteinTarget: plan.proteinasMetaG.toDouble(),
      carbsCurrent: plan.carbohidratosConsumidas,
      carbsTarget: plan.carbohidratosMetaG.toDouble(),
      fatCurrent: plan.grasasConsumidas,
      fatTarget: plan.grasasMetaG.toDouble(),
      timestampIso: DateTime.now().toUtc().toIso8601String(),
    );

    final success = await _homeWidgetService.syncMacrosWidget(payload);
    this.state = success;
  }
}

final widgetSyncProvider = StateNotifierProvider<WidgetSyncNotifier, bool>((ref) {
  return WidgetSyncNotifier(ref, ref.watch(homeWidgetServiceProvider));
});
