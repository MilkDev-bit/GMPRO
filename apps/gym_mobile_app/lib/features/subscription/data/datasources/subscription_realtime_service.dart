/// @file lib/features/subscription/data/datasources/subscription_realtime_service.dart
/// @description Escucha en tiempo real (Supabase PostgreSQL Realtime Channels) la fila
/// de suscripción del socio. Cuando el recepcionista registra un pago en efectivo y
/// payment-service actualiza `estado` a 'active', Supabase emite el evento UPDATE y la
/// app desbloquea los módulos al instante — sin cerrar ni reabrir la aplicación.
///
/// DISEÑO DEFENSIVO: si Supabase no está inicializado o configurado, el servicio
/// queda inerte (no lanza), permitiendo que el fallback por HTTP/polling siga operando.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/app_config.dart';
import '../models/user_subscription_model.dart';

class SubscriptionRealtimeService {
  RealtimeChannel? _channel;

  /// Abre un canal filtrado por `usuario_id` sobre payment_service_db.suscripciones.
  ///
  /// [onChanged] recibe el estado más reciente ya mapeado a [UserSubscriptionModel].
  void subscribe({
    required String usuarioId,
    required void Function(UserSubscriptionModel subscription) onChanged,
  }) {
    if (!AppConfig.isSupabaseConfigured) return;

    final SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      // Supabase.initialize() aún no se ejecutó en main.dart; se omite el realtime.
      return;
    }

    // Cerrar cualquier canal previo antes de reabrir (evita listeners duplicados).
    unsubscribe();

    _channel = client
        .channel('public:suscripciones:$usuarioId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // INSERT | UPDATE | DELETE
          schema: 'payment_service_db',
          table: 'suscripciones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: usuarioId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            onChanged(UserSubscriptionModel.fromJson(record));
          },
        )
        .subscribe();
  }

  /// Cierra el canal y libera la conexión Realtime.
  void unsubscribe() {
    final channel = _channel;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {
        // Cliente no inicializado; nada que liberar.
      }
      _channel = null;
    }
  }
}
