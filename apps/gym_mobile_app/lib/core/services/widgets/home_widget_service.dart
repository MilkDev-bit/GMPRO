/// @file lib/core/services/widgets/home_widget_service.dart
/// @description Servicio para gestionar y actualizar widgets en la pantalla de inicio
/// (WidgetKit para iOS y AppWidgetProvider para Android) mediante MethodChannel y almacenamiento compartido.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'widget_payloads.dart';

abstract class HomeWidgetService {
  /// Envía y sincroniza la última lectura de macros con los widgets de la pantalla de inicio.
  Future<bool> syncMacrosWidget(MacrosWidgetPayload payload);

  /// Forza la recarga de las líneas de tiempo de los widgets instalados por el usuario.
  Future<void> reloadAllWidgets();
}

class HomeWidgetServiceImpl implements HomeWidgetService {
  static const MethodChannel _channel = MethodChannel('com.gympro.widgets/sync');
  static const String _appGroupId = 'group.com.gympro.mobile';
  static const String _androidWidgetProviderName = 'com.gympro.mobile.widgets.GymProMacrosWidget';

  @override
  Future<bool> syncMacrosWidget(MacrosWidgetPayload payload) async {
    try {
      if (kDebugMode) {
        debugPrint('[HomeWidgetService] Sincronizando macros con AppGroup/SharedPreferences: ${payload.toMap()}');
      }

      final mapData = payload.toMap();
      mapData['app_group_id'] = _appGroupId;
      mapData['android_provider'] = _androidWidgetProviderName;

      // Invocamos el canal nativo que guarda en UserDefaults(suiteName: appGroup)
      // / SharedPreferences y notifica al WidgetCenter / AppWidgetManager
      final bool success = await _channel.invokeMethod('updateMacrosWidget', mapData) as bool? ?? true;
      return success;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeWidgetService] Error sincronizando con el widget nativo: ${e.message}');
      }
      return false;
    }
  }

  @override
  Future<void> reloadAllWidgets() async {
    try {
      await _channel.invokeMethod('reloadAllWidgets', {
        'app_group_id': _appGroupId,
        'android_provider': _androidWidgetProviderName,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeWidgetService] Error recargando widgets nativos: ${e.message}');
      }
    }
  }
}
