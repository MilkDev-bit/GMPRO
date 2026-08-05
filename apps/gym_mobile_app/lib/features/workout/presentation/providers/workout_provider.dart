/// @file lib/features/workout/presentation/providers/workout_provider.dart
/// @description Proveedor Riverpod para el estado del plan de rutina IA con datos anatómicos.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/workout_entities.dart';

// Estado de la pantalla de rutina
class WorkoutState {
  const WorkoutState({
    this.plan,
    this.isLoading = false,
    this.error,
  });

  final WorkoutPlan? plan;
  final bool isLoading;
  final String? error;

  WorkoutState copyWith({WorkoutPlan? plan, bool? isLoading, String? error}) {
    return WorkoutState(
      plan:      plan ?? this.plan,
      isLoading: isLoading ?? this.isLoading,
      error:     error,
    );
  }
}

class WorkoutNotifier extends StateNotifier<WorkoutState> {
  WorkoutNotifier(this._apiClient) : super(const WorkoutState()) {
    // Cargar plan o fallback al iniciar
    if (state.plan == null) {
      state = state.copyWith(plan: _fallbackPlan);
    }
  }

  final ApiClient _apiClient;

  /// Solicita al ai-service en Railway una nueva rutina personalizada
  Future<void> generateRoutinePlan({
    required String objetivo,
    required String nivel,
    required List<String> lesiones,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/ai/routine',
        data: {
          'objetivo':      objetivo,
          'nivel':         nivel,
          'lesiones':      lesiones,
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
        error: e.message ?? 'Error de conexión. Mostrando rutina demostrativa.',
      );
    }
  }

  /// Plan demostrativo offline enriquecido con mapeo anatómico exacto (Fitia / Jefit style)
  static const WorkoutPlan _fallbackPlan = WorkoutPlan(
    nombre: 'Hipertrofia Estética — División 4 Días',
    descripcion: 'Enfoque en proporción anatómica en forma de V (Hombros anchos, cintura compacta y piernas fuertes).',
    nivel: 'intermedio',
    objetivo: 'hipertrofia',
    dias: [
      WorkoutDay(
        dia: 'Día 1 — Pecho y Tríceps (Empuje)',
        enfoqueMusculares: ['Fuerza Superior y Tensión Mecánica'],
        ejercicios: [
          WorkoutExercise(
            ejercicioId: 'wger-123',
            nombre: 'Press de Banca Inclinado con Mancuernas',
            musculos_primarios: ['pectoral_mayor_superior', 'triceps_braquial'],
            musculos_secundarios: ['deltoides_anterior'],
            series: 4,
            repeticiones: '8-10',
            descansoSeg: 90,
            notas: 'Contrae 2 segundos arriba. Ángulo de banca a 30° exactos.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-124',
            nombre: 'Fondos en Paralelas con Lastre (Dips)',
            musculos_primarios: ['pectoral_mayor_inferior', 'triceps_braquial'],
            musculos_secundarios: ['deltoides_anterior'],
            series: 4,
            repeticiones: '10-12',
            descansoSeg: 75,
            notas: 'Inclina el torso ligeramente al frente para enfatizar el pectoral inferior.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-125',
            nombre: 'Aperturas en Polea Alta (Crossover)',
            musculos_primarios: ['pectoral_mayor_medio'],
            musculos_secundarios: [],
            series: 3,
            repeticiones: '12-15',
            descansoSeg: 60,
            notas: 'Cruza las manos al frente y mantén contracción isométrica 1 segundo.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-126',
            nombre: 'Extensión de Tríceps en Polea con Cuerda',
            musculos_primarios: ['triceps_braquial'],
            musculos_secundarios: ['anconeo'],
            series: 4,
            repeticiones: '12-15',
            descansoSeg: 60,
            notas: 'Separa la cuerda al final del movimiento abriendo las muñecas.',
          ),
        ],
      ),
      WorkoutDay(
        dia: 'Día 2 — Espalda y Bíceps (Tracción)',
        enfoqueMusculares: ['Amplitud dorsal y densidad del core'],
        ejercicios: [
          WorkoutExercise(
            ejercicioId: 'wger-201',
            nombre: 'Dominadas Pronadas con Carga (Pull-ups)',
            musculos_primarios: ['dorsal_ancho'],
            musculos_secundarios: ['biceps_braquial', 'trapecio', 'romboide'],
            series: 4,
            repeticiones: '6-8',
            descansoSeg: 120,
            notas: 'Rango de recorrido completo desde bloqueo escapular inferior.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-202',
            nombre: 'Remo con Barra Pendlay',
            musculos_primarios: ['dorsal_ancho', 'trapecio', 'romboide'],
            musculos_secundarios: ['biceps_braquial', 'erector_espinal'],
            series: 4,
            repeticiones: '8-10',
            descansoSeg: 90,
            notas: 'Torso paralelo al suelo. Explosivo concéntrico y control excéntrico.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-203',
            nombre: 'Curl de Bíceps con Barra EZ en Banco Scott',
            musculos_primarios: ['biceps_braquial', 'braquial_anterior'],
            musculos_secundarios: ['braquiorradial'],
            series: 4,
            repeticiones: '10-12',
            descansoSeg: 60,
            notas: 'Mantén los codos pegados al cojín sin balanceo.',
          ),
        ],
      ),
      WorkoutDay(
        dia: 'Día 3 — Pierna Completa (Cuádriceps & Glúteo)',
        enfoqueMusculares: ['Desarrollo de tren inferior y estabilidad'],
        ejercicios: [
          WorkoutExercise(
            ejercicioId: 'wger-301',
            nombre: 'Sentadilla Trasera con Barra Alta (Back Squat)',
            musculos_primarios: ['cuadriceps', 'gluteo_mayor'],
            musculos_secundarios: ['isquiotibiales', 'erector_espinal'],
            series: 5,
            repeticiones: '6-8',
            descansoSeg: 150,
            notas: 'Profundidad bajo la paralela con core activo en todo momento.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-302',
            nombre: 'Prensa Inclinada a 45 Grados',
            musculos_primarios: ['cuadriceps'],
            musculos_secundarios: ['gluteo_mayor'],
            series: 4,
            repeticiones: '12-15',
            descansoSeg: 90,
            notas: 'No bloquees las rodillas al extender en la parte superior.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-303',
            nombre: 'Elevación de Talones de Pie para Pantorrilla',
            musculos_primarios: ['gastrocnemio', 'soleo'],
            musculos_secundarios: [],
            series: 4,
            repeticiones: '15-20',
            descansoSeg: 45,
            notas: 'Pausa de 2 segundos en el máximo estiramiento inferior.',
          ),
        ],
      ),
      WorkoutDay(
        dia: 'Día 4 — Hombro y Core (Deltoides & Abdomen)',
        enfoqueMusculares: ['Estética 3D de hombro y cinturón abdominal'],
        ejercicios: [
          WorkoutExercise(
            ejercicioId: 'wger-401',
            nombre: 'Press Militar con Mancuernas Sentado',
            musculos_primarios: ['deltoides_anterior', 'deltoides_lateral'],
            musculos_secundarios: ['triceps_braquial', 'trapecio'],
            series: 4,
            repeticiones: '8-10',
            descansoSeg: 90,
            notas: 'Empuje vertical sin arquería excesiva en la zona lumbar.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-402',
            nombre: 'Elevaciones Laterales con Polea Baja',
            musculos_primarios: ['deltoides_lateral'],
            musculos_secundarios: [],
            series: 4,
            repeticiones: '12-15',
            descansoSeg: 60,
            notas: 'Tensión constante en todo el recorrido cruzando el cable tras el cuerpo.',
          ),
          WorkoutExercise(
            ejercicioId: 'wger-403',
            nombre: 'Elevación de Piernas Colgado en Barra (Hanging Leg Raise)',
            musculos_primarios: ['recto_abdominal', 'oblicuos'],
            musculos_secundarios: [],
            series: 4,
            repeticiones: '12-15',
            descansoSeg: 60,
            notas: 'Enróscate elevando la pelvis, no solo flexionando las caderas.',
          ),
        ],
      ),
    ],
  );
}

final workoutProvider = StateNotifierProvider<WorkoutNotifier, WorkoutState>((ref) {
  final api = ref.watch(apiClientProvider);
  return WorkoutNotifier(api);
});
