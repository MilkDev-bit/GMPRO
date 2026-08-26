/// @file lib/features/workout/domain/training/session_builder.dart
/// @description Puente PURO entre el plan generado por IA (WorkoutExercise) y el
/// motor de progresión. Traduce "8-12 reps" y el nombre del ejercicio a una
/// ProgressionConfig, y calcula el objetivo de hoy con el historial del socio.
///
/// Todo es determinista y sin dependencias de Flutter → testeable con flutter test.

import '../entities/workout_entities.dart';
import 'set_log.dart';
import 'progression.dart';

/// Rango de repeticiones parseado desde un texto libre ("8-12", "10", "AMRAP").
class RepRange {
  const RepRange(this.min, this.max);
  final int min;
  final int max;
}

/// Extrae min/max de un texto de reps. Tolera "8-12", "8 a 12", "10", "12+".
RepRange parseRepRange(String raw, {int fallbackMin = 8, int fallbackMax = 12}) {
  final nums = RegExp(r'\d+')
      .allMatches(raw)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  if (nums.isEmpty) return RepRange(fallbackMin, fallbackMax);
  if (nums.length == 1) return RepRange(nums.first, nums.first);
  final a = nums[0], b = nums[1];
  return RepRange(a <= b ? a : b, a <= b ? b : a);
}

// Heurísticas de nombre (sin acentos, minúsculas) para inferir el tipo.
const _timedKeywords = [
  'plancha', 'plank', 'isometric', 'isometr', 'hold', 'wall sit', 'sentadilla isometrica',
  'carry', 'farmer', 'acarreo', 'hang', 'colgado', 'hollow',
];
const _bodyweightKeywords = [
  'flexion', 'flexiones', 'push-up', 'push up', 'pushup', 'lagartija',
  'dominada', 'pull-up', 'pull up', 'pullup', 'chin-up',
  'fondo', 'fondos', 'dip', 'dips',
  'burpee', 'zancada corporal', 'jumping', 'mountain climber',
];
const _perSideKeywords = [
  'por lado', 'unilateral', 'una pierna', 'un brazo', 'single-arm', 'single arm',
  'single-leg', 'single leg', 'a una mano', 'bulgaro', 'bulgara', 'zancada', 'lunge',
];

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[áàä]'), 'a')
    .replaceAll(RegExp(r'[éèë]'), 'e')
    .replaceAll(RegExp(r'[íìï]'), 'i')
    .replaceAll(RegExp(r'[óòö]'), 'o')
    .replaceAll(RegExp(r'[úùü]'), 'u');

bool _hasAny(String name, List<String> keys) {
  final n = _norm(name);
  return keys.any(n.contains);
}

/// Infiere cómo se registra el ejercicio a partir de su nombre.
ExerciseKind inferExerciseKind(String nombre) {
  if (_hasAny(nombre, _timedKeywords)) return ExerciseKind.timed;
  if (_hasAny(nombre, _bodyweightKeywords)) return ExerciseKind.bodyweight;
  return ExerciseKind.weighted;
}

/// ¿Es un ejercicio "por lado" (avanza en pares)?
bool inferPerSide(String nombre) => _hasAny(nombre, _perSideKeywords);

/// Regla de progresión por defecto según el objetivo de la rutina.
ProgressionRuleType defaultRuleForGoal(String objetivo) {
  switch (_norm(objetivo)) {
    case 'fuerza':
      return ProgressionRuleType.linear;
    case 'resistencia':
      return ProgressionRuleType.doubleProgression;
    case 'hipertrofia':
    default:
      return ProgressionRuleType.doubleProgression;
  }
}

/// Construye la configuración de progresión para un ejercicio del plan.
ProgressionConfig buildConfig(
  WorkoutExercise ex, {
  required String objetivo,
  ProgressionRuleType? ruleOverride,
}) {
  final kind = inferExerciseKind(ex.nombre);
  final perSide = inferPerSide(ex.nombre);
  final range = parseRepRange(ex.repeticiones);

  // Los ejercicios de peso corporal progresan en reps salvo override explícito.
  ProgressionRuleType rule = ruleOverride ??
      (kind == ExerciseKind.bodyweight
          ? ProgressionRuleType.bodyweightReps
          : kind == ExerciseKind.timed
              ? ProgressionRuleType.addTime
              : defaultRuleForGoal(objetivo));

  return ProgressionConfig(
    rule: rule,
    kind: kind,
    targetSets: ex.series,
    repMin: range.min,
    repMax: range.max,
    perSide: perSide,
    // Incrementos sensatos por defecto; ajustables por ejercicio/rutina.
    incrementKg: kind == ExerciseKind.weighted ? 2.5 : 2.5,
    roundingKg: 2.5,
    stallLimit: 3,
    deloadPct: 0.10,
  );
}

/// Un ejercicio listo para entrenar: config + objetivo de hoy (ya calculado).
class GuidedExercisePlan {
  const GuidedExercisePlan({
    required this.exercise,
    required this.config,
    required this.target,
  });

  final WorkoutExercise exercise;
  final ProgressionConfig config;
  final ProgressionTarget target;

  int get targetSets => target.sets ?? config.targetSets;
}

/// Construye el plan guiado de un ejercicio: objetivo derivado del historial
/// (pre-carga "los pesos de la última vez", openGym).
GuidedExercisePlan buildGuidedExercise(
  WorkoutExercise ex, {
  required String objetivo,
  required List<ExerciseSession> history,
  ProgressionRuleType? ruleOverride,
}) {
  final cfg = buildConfig(ex, objetivo: objetivo, ruleOverride: ruleOverride);
  final target = nextTarget(cfg: cfg, history: history);
  return GuidedExercisePlan(exercise: ex, config: cfg, target: target);
}
