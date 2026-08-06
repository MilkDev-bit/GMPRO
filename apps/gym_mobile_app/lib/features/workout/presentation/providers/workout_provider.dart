/// @file lib/features/workout/presentation/providers/workout_provider.dart
/// @description Proveedor Riverpod para el estado del plan de rutina IA. La rutina
/// se genera EN EL BACKEND (ai-service), que arma los ejercicios a partir del
/// catálogo de wger y de las características del socio. Ya NO hay plan mock local:
/// arranca sin plan hasta que el socio genera con sus datos reales.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/workout_entities.dart';

/// Perfil de entrenamiento del socio: los datos que alimentan la generación de
/// rutinas del ai-service (objetivo, nivel, días/semana, lesiones). Se persiste
/// y se edita desde el formulario o desde Ajustes.
class WorkoutProfile {
  const WorkoutProfile({
    this.objetivo = 'hipertrofia',
    this.nivel = 'intermedio',
    this.diasPorSemana = 4,
    this.lesiones = 'ninguna',
    this.isComplete = false,
  });

  final String objetivo;
  final String nivel;
  final int diasPorSemana;
  final String lesiones;

  /// true una vez que el socio generó/guardó con sus propios datos.
  final bool isComplete;

  static const Map<String, String> objetivoLabels = {
    'hipertrofia': 'Hipertrofia',
    'fuerza': 'Fuerza',
    'resistencia': 'Resistencia',
    'perdida_grasa': 'Pérdida de grasa',
  };
  static const Map<String, String> nivelLabels = {
    'principiante': 'Principiante',
    'intermedio': 'Intermedio',
    'avanzado': 'Avanzado',
  };

  String get objetivoLabel => objetivoLabels[objetivo] ?? objetivo;
  String get nivelLabel => nivelLabels[nivel] ?? nivel;

  WorkoutProfile copyWith({
    String? objetivo,
    String? nivel,
    int? diasPorSemana,
    String? lesiones,
    bool? isComplete,
  }) {
    return WorkoutProfile(
      objetivo: objetivo ?? this.objetivo,
      nivel: nivel ?? this.nivel,
      diasPorSemana: diasPorSemana ?? this.diasPorSemana,
      lesiones: lesiones ?? this.lesiones,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() => {
        'objetivo': objetivo,
        'nivel': nivel,
        'diasPorSemana': diasPorSemana,
        'lesiones': lesiones,
        'isComplete': isComplete,
      };

  factory WorkoutProfile.fromJson(Map<String, dynamic> j) => WorkoutProfile(
        objetivo: (j['objetivo'] as String?) ?? 'hipertrofia',
        nivel: (j['nivel'] as String?) ?? 'intermedio',
        diasPorSemana: (j['diasPorSemana'] as num?)?.toInt() ?? 4,
        lesiones: (j['lesiones'] as String?) ?? 'ninguna',
        isComplete: (j['isComplete'] as bool?) ?? true,
      );
}

// Estado de la pantalla de rutina
class WorkoutState {
  const WorkoutState({
    this.plan,
    this.isLoading = false,
    this.error,
    this.profile = const WorkoutProfile(),
  });

  final WorkoutPlan? plan;
  final bool isLoading;
  final String? error;

  /// Perfil actual del socio (persistido). isComplete=false hasta configurarlo.
  final WorkoutProfile profile;

  WorkoutState copyWith({
    WorkoutPlan? plan,
    bool? isLoading,
    String? error,
    WorkoutProfile? profile,
  }) {
    return WorkoutState(
      plan:      plan ?? this.plan,
      isLoading: isLoading ?? this.isLoading,
      error:     error,
      profile:   profile ?? this.profile,
    );
  }
}

class WorkoutNotifier extends StateNotifier<WorkoutState> {
  // Arranca SIN plan (plan == null): la pantalla muestra "genera tu rutina" hasta
  // que el socio la crea con sus datos reales. Ya NO cargamos un plan mock.
  WorkoutNotifier(this._apiClient, this._storage) : super(const WorkoutState()) {
    _loadProfile();
  }

  final ApiClient _apiClient;
  final SecureStorageService _storage;

  /// Carga el perfil de entrenamiento persistido al arrancar (para prellenar el
  /// formulario y que Ajustes muestre los datos reales). No genera rutina sola.
  Future<void> _loadProfile() async {
    final json = await _storage.getWorkoutProfile();
    if (json == null) return;
    final p = WorkoutProfile.fromJson(json);
    if (mounted) state = state.copyWith(profile: p);
  }

  Future<void> _persistProfile(WorkoutProfile p) =>
      _storage.saveWorkoutProfile(p.toJson());

  /// Solicita al ai-service (Railway) una nueva rutina personalizada. El backend
  /// arma los ejercicios desde el catálogo de wger y aplica las características
  /// del socio. Los datos físicos (peso/estatura/edad/actividad) se toman del
  /// perfil de dieta persistido para que la rutina también los considere.
  Future<void> generateRoutinePlan({
    String? objetivo,
    String? nivel,
    int? diasPorSemana,
    String? lesiones,
  }) async {
    final profile = state.profile.copyWith(
      objetivo: objetivo,
      nivel: nivel,
      diasPorSemana: diasPorSemana,
      lesiones: lesiones,
      isComplete: true,
    );
    unawaited(_persistProfile(profile));

    state = state.copyWith(isLoading: true, error: null, profile: profile);

    try {
      // Datos físicos compartidos desde el perfil de dieta (si existe).
      final diet = await _storage.getDietProfile();

      final response = await _apiClient.dio.post(
        // URL ABSOLUTA del ai-service. Antes era '/api/v1/ai/routine' relativa →
        // se resolvía contra el baseUrl del dio (auth-service) → 404 → la app se
        // quedaba con el plan MOCK. El endpoint real es /recommendations/routine.
        '${AppConfig.aiServiceBaseUrl}/recommendations/routine',
        data: {
          'objetivo':      profile.objetivo,
          'nivel':         profile.nivel,
          'diasPorSemana': profile.diasPorSemana,
          'lesiones':      profile.lesiones,
          if (diet != null) 'pesoKg':     diet['pesoKg'],
          if (diet != null) 'estaturaCm': diet['estaturaCm'],
          if (diet != null) 'edad':       diet['edad'],
          if (diet != null) 'actividad':  diet['actividad'],
        },
      );

      if (response.data['success'] == true && response.data['data'] != null) {
        final plan = await WorkoutPlan.parseInBackground(
          response.data['data'] as Map<String, dynamic>,
        );
        state = state.copyWith(plan: plan, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.data['error'] as String? ?? 'Error al generar la rutina desde AI Service',
        );
      }
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _friendlyDioError(e),
      );
    }
  }

  /// Convierte un DioException en un mensaje amigable para el usuario.
  static String _friendlyDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['error'] is String) {
      return data['error'] as String;
    }
    switch (e.response?.statusCode) {
      case 429:
        return 'Has alcanzado el límite de generaciones por hoy. '
               'Intenta de nuevo mañana.';
      case 401:
        return 'Tu sesión expiró. Cierra sesión y vuelve a iniciar.';
      case 403:
        return 'No tienes permiso para esta acción. Verifica tu membresía.';
      case 502:
        return 'El servicio de IA no está disponible temporalmente. '
               'Intenta en unos minutos.';
      case 503:
        return 'El servidor está en mantenimiento. Intenta en unos minutos.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          return 'La generación tardó demasiado. Verifica tu conexión e intenta de nuevo.';
        }
        if (e.type == DioExceptionType.connectionError) {
          return 'Sin conexión a internet. Verifica tu red e intenta de nuevo.';
        }
        return 'Error al conectar con el servidor. Intenta de nuevo.';
    }
  }

  /// Guarda el perfil editado desde Ajustes. Persiste y, si ya existe una rutina
  /// generada, la recalcula con los nuevos datos.
  Future<void> updateProfile({
    String? objetivo,
    String? nivel,
    int? diasPorSemana,
    String? lesiones,
  }) async {
    final p = state.profile.copyWith(
      objetivo: objetivo,
      nivel: nivel,
      diasPorSemana: diasPorSemana,
      lesiones: lesiones,
      isComplete: true,
    );
    state = state.copyWith(profile: p);
    await _persistProfile(p);
    if (state.plan != null) await generateRoutinePlan();
  }
}

final workoutProvider = StateNotifierProvider<WorkoutNotifier, WorkoutState>((ref) {
  final api = ref.watch(apiClientProvider);
  final storage = ref.watch(secureStorageProvider);
  return WorkoutNotifier(api, storage);
});
