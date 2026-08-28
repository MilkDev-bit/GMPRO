/// @file lib/features/workout/presentation/screens/workout_plan_screen.dart
/// @description Pantalla completa del plan de rutina con mapa anatómico interactivo,
/// PageView de ejercicios con swipe, y tarjetas de series/reps con glassmorphism.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/services/index.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/workout_entities.dart';
import '../../domain/muscle_catalog.dart';
import '../widgets/interactive_anatomy_map.dart';
import '../widgets/workout_profile_sheet.dart';
import '../../../nutrition/presentation/widgets/weight_check_banner.dart';
import 'guided_workout_screen.dart';
import 'stats_screen.dart';

class WorkoutPlanScreen extends ConsumerStatefulWidget {
  const WorkoutPlanScreen({super.key, required this.plan});
  final WorkoutPlan plan;

  @override
  ConsumerState<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends ConsumerState<WorkoutPlanScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _exercisePageController;
  late final TabController _dayTabController;
  int _currentExerciseIndex = 0;
  int _currentDayIndex = 0;
  Color _headerColor = AppColors.neonPink;

  WorkoutDay get _currentDay => widget.plan.dias[_currentDayIndex];
  List<WorkoutExercise> get _currentExercises => _currentDay.ejercicios;

  @override
  void initState() {
    super.initState();
    _exercisePageController = PageController(viewportFraction: 0.88);
    _dayTabController = TabController(
      length: widget.plan.dias.length,
      vsync: this,
    );
    _dayTabController.addListener(() {
      if (_dayTabController.indexIsChanging) return;
      setState(() {
        _currentDayIndex = _dayTabController.index;
        _currentExerciseIndex = 0;
      });
      _exercisePageController.jumpToPage(0);
      _syncCurrentExerciseToWatch(0);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCurrentExerciseToWatch(0);
    });
  }

  void _syncCurrentExerciseToWatch(int index) {
    if (index < 0 || index >= _currentExercises.length) return;
    final exercise = _currentExercises[index];
    _updateHeaderColor(exercise);
    try {
      ref.read(wearableControllerProvider.notifier).syncWorkout(
            exerciseId: exercise.ejercicioId,
            exerciseName: exercise.nombre,
            currentSeries: 1,
            totalSeries: exercise.series,
            reps: exercise.repeticiones,
            restSeconds: exercise.descansoSeg,
          );
    } catch (e) {
      debugPrint('⚠️ [WorkoutPlanScreen] No se pudo sincronizar con reloj: $e');
    }
  }

  /// Lanza el runner de entrenamiento guiado para el día activo. Pasa el objetivo del
  /// plan y el nombre del día como rótulo. El runner pre-carga pesos desde el historial.
  void _startGuidedWorkout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuidedWorkoutScreen(
          day: _currentDay,
          objetivo: widget.plan.objetivo,
          routineName: _currentDay.dia,
        ),
      ),
    );
  }

  Future<void> _updateHeaderColor(WorkoutExercise exercise) async {
    // Sin foto real → usamos el color del músculo (sin llamada de red).
    final url = _exerciseImageUrl(exercise);
    if (url == null) {
      if (mounted) setState(() => _headerColor = _muscleAccent(exercise));
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
      );
      if (mounted) {
        setState(() {
          _headerColor = palette.dominantColor?.color ?? _muscleAccent(exercise);
        });
      }
    } catch (e) {
      debugPrint('Error generating palette: $e');
      if (mounted) setState(() => _headerColor = _muscleAccent(exercise));
    }
  }

  @override
  void dispose() {
    _exercisePageController.dispose();
    _dayTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // SafeArea(top) para que el título no quede bajo el notch/isla dinámica.
      // El SliverAppBar va con primary:false para no duplicar el inset.
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── STICKY APP BAR con nombre del plan ─────────────────────────
          SliverAppBar(
            primary: false,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 64, 16),
              // Título corto fijo + subtítulo con el tipo/nivel: nunca desborda,
              // por largo que sea el nombre generado por la IA.
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.plan.objetivo} · ${widget.plan.nivel}'.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neonPurple,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Plan semanal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 21,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              background: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_headerColor.withValues(alpha: 0.32), AppColors.background],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.neonPurple),
                tooltip: 'Regenerar rutina con IA',
                onPressed: () => WorkoutProfileSheet.show(context),
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ── TABS DE DÍAS ────────────────────────────────────────────────
          // pinned: false → antes, con el SliverAppBar pinned + este header
          // pinned encima, el segundo se quedaba sin paintExtent y Flutter
          // lanzaba "layoutExtent exceeds paintExtent", rompiendo TODO el
          // viewport (pantalla negra + cascada de "Null check"/overflow).
          SliverPersistentHeader(
            pinned: false,
            delegate: _DayTabsDelegate(
              tabController: _dayTabController,
              days: widget.plan.dias,
            ),
          ),

          // ── CONTENIDO PRINCIPAL ─────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
            sliver: SliverList.list(
              children: [
                // ── SEGUIMIENTO DE PESO (recordatorio / reajuste de AMBOS planes) ──
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: WeightCheckBanner(),
                ),

                // ── CTA PRIMARIO: EMPEZAR ENTRENAMIENTO GUIADO ────────────
                if (_currentExercises.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _StartWorkoutButton(
                      dayLabel: _currentDay.dia.split('—').first.trim(),
                      onTap: _startGuidedWorkout,
                    ),
                  ),

                // ── ACCESO A ESTADÍSTICAS (botón claro, sobre el mapa) ─────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _StatsAccessButton(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StatsScreen()),
                    ),
                  ),
                ),

                // ── MAPA ANATÓMICO ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _currentExercises.isNotEmpty
                      ? InteractiveAnatomyMap(
                          exercises: _currentExercises,
                          initialIndex: _currentExerciseIndex,
                          height: 430,
                          onExerciseChanged: (index) {
                            setState(() => _currentExerciseIndex = index);
                            _exercisePageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),

                // ── PAGE VIEW DE TARJETAS DE EJERCICIO ────────────────────
                SizedBox(
                  height: 210,
                  child: PageView.builder(
                    controller: _exercisePageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentExerciseIndex = index);
                      _syncCurrentExerciseToWatch(index);
                    },
                    itemCount: _currentExercises.length,
                    itemBuilder: (context, index) {
                      final exercise = _currentExercises[index];
                      final isActive = index == _currentExerciseIndex;
                      return AnimatedScale(
                        scale: isActive ? 1.0 : 0.94,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _ExerciseCard(
                            exercise: exercise,
                            isActive: isActive,
                            exerciseNumber: index + 1,
                            totalExercises: _currentExercises.length,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // ── INDICADORES DE PÁGINA ─────────────────────────────────
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _currentExercises.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        width: i == _currentExerciseIndex ? 20 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _currentExerciseIndex
                              ? AppColors.neonPink
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── RESUMEN DE MÚSCULOS DEL DÍA ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _DayMuscleSummary(day: _currentDay),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: _MiniPlayer(
        exercise: _currentExercises.isNotEmpty ? _currentExercises[_currentExerciseIndex] : null,
        onStart: _currentExercises.isEmpty ? null : _startGuidedWorkout,
        onNext: () {
          if (_currentExerciseIndex < _currentExercises.length - 1) {
            final nextIndex = _currentExerciseIndex + 1;
            setState(() => _currentExerciseIndex = nextIndex);
            _exercisePageController.animateToPage(
              nextIndex,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA PRIMARIO: EMPEZAR ENTRENAMIENTO GUIADO
// ─────────────────────────────────────────────────────────────────────────────
class _StartWorkoutButton extends StatelessWidget {
  const _StartWorkoutButton({required this.dayLabel, required this.onTap});
  final String dayLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.neonEmerald;
    return Pressable(
      haptic: PressHaptic.medium,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [emerald.withValues(alpha: 0.22), emerald.withValues(alpha: 0.12)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: emerald.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Empezar entrenamiento',
                    style: AppTypography.buttonLabel.copyWith(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Guiado · $dayLabel',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: emerald, size: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN DE ACCESO A ESTADÍSTICAS (peso corporal + heatmap)
// ─────────────────────────────────────────────────────────────────────────────
class _StatsAccessButton extends StatelessWidget {
  const _StatsAccessButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cyan = AppColors.accentCyanOf(context);
    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cyan.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cyan.withValues(alpha: 0.40), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mi progreso',
                    style: AppTypography.buttonLabel.copyWith(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Peso corporal y actividad',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cyan, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE EJERCICIO
// ─────────────────────────────────────────────────────────────────────────────
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.isActive,
    required this.exerciseNumber,
    required this.totalExercises,
  });
  final WorkoutExercise exercise;
  final bool isActive;
  final int exerciseNumber;
  final int totalExercises;

  @override
  Widget build(BuildContext context) {
    Color accentColor = AppColors.neonPink;
    if (exercise.musculos_primarios.isNotEmpty) {
      final m = MuscleCatalog.byKey(exercise.musculos_primarios.first);
      if (m != null) accentColor = m.color;
    }

    return GestureDetector(
      onTap: () => showExerciseDetailSheet(context, exercise),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surfaceElevatedOf(context) : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? accentColor.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.05),
            width: isActive ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // La portada/gif del ejercicio ya NO va en la tarjeta de lista; solo
            // se muestra en el detalle del ejercicio.
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    exercise.nombre,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isActive ? accentColor : Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.series} Series • ${exercise.repeticiones}',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Play Icon
            Icon(
              Icons.play_circle_fill_rounded,
              color: isActive ? accentColor : Colors.white,
              size: 32,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Portada del ejercicio: imagen real (wger) → video → placeholder.
/// URL de imagen REAL del ejercicio (wger). null si no hay → se usa el fallback.
String? _exerciseImageUrl(WorkoutExercise ex) {
  // Prioridad: GIF animado de la ejecución → imagen estática de wger → video.
  // CachedNetworkImage reproduce GIFs animados directamente como portada.
  if (ex.gifUrl?.isNotEmpty == true) return ex.gifUrl;
  if (ex.imageUrl?.isNotEmpty == true) return ex.imageUrl;
  if (ex.videoUrl?.isNotEmpty == true) return ex.videoUrl;
  return null;
}

// ── Fallback por grupo muscular (cuando wger no tiene foto del ejercicio) ──────
String _muscleGroupKey(WorkoutExercise ex) {
  final k = ex.musculos_primarios.isNotEmpty ? ex.musculos_primarios.first : '';
  if (k.contains('pectoral')) return 'chest';
  if (k.contains('dorsal') || k.contains('trapecio') || k.contains('romboide') ||
      k.contains('redondo') || k.contains('erector')) return 'back';
  if (k.contains('deltoides')) return 'shoulders';
  if (k.contains('biceps_braq') || k.contains('triceps') || k.contains('braqui')) return 'arms';
  if (k.contains('abdominal') || k.contains('oblicuo') || k.contains('transverso')) return 'core';
  if (k.contains('cuadriceps') || k.contains('femoral') || k.contains('isquio') ||
      k.contains('gluteo') || k.contains('gemelo') || k.contains('soleo') ||
      k.contains('tibial')) return 'legs';
  return 'default';
}

const Map<String, IconData> _kGroupIcons = {
  'chest': Icons.fitness_center_rounded,
  'back': Icons.rowing_rounded,
  'shoulders': Icons.sports_gymnastics_rounded,
  'arms': Icons.sports_mma_rounded,
  'core': Icons.self_improvement_rounded,
  'legs': Icons.directions_run_rounded,
  'default': Icons.fitness_center_rounded,
};
const Map<String, String> _kGroupLabels = {
  'chest': 'Pecho', 'back': 'Espalda', 'shoulders': 'Hombro',
  'arms': 'Brazo', 'core': 'Core', 'legs': 'Pierna', 'default': 'Ejercicio',
};

Color _muscleAccent(WorkoutExercise ex) {
  if (ex.musculos_primarios.isNotEmpty) {
    final m = MuscleCatalog.byKey(ex.musculos_primarios.first);
    if (m != null) return m.color;
  }
  return AppColors.neonPurple;
}

/// Portada del ejercicio: imagen real (wger) o, si no hay, un fondo con degradado
/// del color del músculo + ícono del grupo, para que NINGÚN ejercicio se vea vacío.
Widget _exerciseCover(WorkoutExercise ex, {required double size, double radius = 14, bool showLabel = false}) {
  final url = _exerciseImageUrl(ex);
  final accent = _muscleAccent(ex);
  final group = _muscleGroupKey(ex);
  final icon = _kGroupIcons[group] ?? Icons.fitness_center_rounded;
  final label = _kGroupLabels[group] ?? 'Ejercicio';

  Widget fallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: 0.55), accent.withValues(alpha: 0.14)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.92), size: size * 0.34),
            if (showLabel) ...[
              const SizedBox(height: 8),
              Text(label,
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ],
        ),
      );

  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: showLabel ? double.infinity : size,
      height: size,
      child: url == null
          ? fallback()
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback(),
              errorWidget: (_, __, ___) => fallback(),
            ),
    ),
  );
}

/// Hoja de detalle del ejercicio: nombre, músculos, series/reps/descanso, notas,
/// y un botón para ver la demostración en wger. Se abre al tocar la tarjeta o el
/// control del mini-player (antes esos toques no hacían nada).
Future<void> showExerciseDetailSheet(BuildContext context, WorkoutExercise ex) {
  Color accent = AppColors.neonPink;
  if (ex.musculos_primarios.isNotEmpty) {
    final m = MuscleCatalog.byKey(ex.musculos_primarios.first);
    if (m != null) accent = m.color;
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevatedOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44, height: 5,
                decoration: BoxDecoration(
                  color: AppColors.glassBorderOf(ctx),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _exerciseCover(ex, size: 180, radius: 18, showLabel: true),
            const SizedBox(height: 16),
            Text(ex.nombre,
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16, runSpacing: 8,
              children: [
                _detailChip(Icons.repeat_rounded, '${ex.series} series'),
                _detailChip(Icons.fitness_center_rounded, '${ex.repeticiones} reps'),
                _detailChip(Icons.timer_outlined, '${ex.descansoSeg}s descanso'),
              ],
            ),
            if (ex.musculos_primarios.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('MÚSCULOS TRABAJADOS',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: ex.allMuscles.map((k) {
                  final m = MuscleCatalog.byKey(k);
                  final label = m?.label ?? k.replaceAll('_', ' ');
                  final c = m?.color ?? accent;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withValues(alpha: 0.4)),
                    ),
                    child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                  );
                }).toList(),
              ),
            ],
            if (ex.notas?.isNotEmpty == true) ...[
              const SizedBox(height: 18),
              Text('TÉCNICA',
                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Text(ex.notas!, style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: Colors.white70)),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Entendido',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, height: 1.0)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _detailChip(IconData icon, String text) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppColors.textMuted),
      const SizedBox(width: 5),
      Text(text, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI-PLAYER FLOTANTE (Spotify Style)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({this.exercise, required this.onNext, this.onStart});
  final WorkoutExercise? exercise;
  final VoidCallback onNext;

  /// Lanza el entrenamiento guiado del día. null = sin ejercicios (oculta el botón).
  final VoidCallback? onStart;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    if (widget.exercise == null) return const SizedBox.shrink();

    final ex = widget.exercise!;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // La portada/gif solo se muestra en el detalle del ejercicio.
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ex.nombre,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${ex.series} Series • ${ex.descansoSeg}s desc.',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Controls: empezar guiado (CTA) + ver detalle + siguiente
            if (widget.onStart != null)
              IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.neonEmerald, size: 32),
                tooltip: 'Empezar entrenamiento guiado',
                onPressed: widget.onStart,
              ),
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 26),
              tooltip: 'Ver ejercicio',
              onPressed: () => showExerciseDetailSheet(context, ex),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
              tooltip: 'Siguiente',
              onPressed: widget.onNext,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESUMEN DE MÚSCULOS DEL DÍA
// ─────────────────────────────────────────────────────────────────────────────
class _DayMuscleSummary extends StatelessWidget {
  const _DayMuscleSummary({required this.day});
  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    // Recopilar todos los músculos únicos del día con frecuencia de aparición
    final Map<String, int> muscleFreq = {};
    for (final ex in day.ejercicios) {
      for (final key in ex.musculos_primarios) {
        muscleFreq[key] = (muscleFreq[key] ?? 0) + 2; // Primario = peso 2
      }
      for (final key in ex.musculos_secundarios) {
        muscleFreq[key] = (muscleFreq[key] ?? 0) + 1; // Secundario = peso 1
      }
    }

    final sortedEntries = muscleFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MÚSCULOS DEL DÍA',
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sortedEntries.take(10).map((entry) {
            final m = MuscleCatalog.byKey(entry.key);
            final isPrimary = entry.value >= 2;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (m?.color ?? AppColors.neonPink).withValues(alpha: isPrimary ? 0.15 : 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (m?.color ?? AppColors.neonPink).withValues(alpha: isPrimary ? 0.4 : 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m?.color ?? AppColors.neonPink,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    m?.label ?? entry.key,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
                      color: isPrimary
                          ? (m?.color ?? AppColors.neonPink)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABS DE DÍAS — SliverPersistentHeaderDelegate
// ─────────────────────────────────────────────────────────────────────────────
class _DayTabsDelegate extends SliverPersistentHeaderDelegate {
  const _DayTabsDelegate({
    required this.tabController,
    required this.days,
  });
  final TabController tabController;
  final List<WorkoutDay> days;

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: TabBar(
        controller: tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        indicatorColor: AppColors.neonPink,
        indicatorWeight: 2,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w400),
        dividerColor: Colors.white.withValues(alpha: 0.06),
        tabs: days
            .map((d) => Tab(text: d.dia.split('—').first.trim()))
            .toList(),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayTabsDelegate old) => false;
}
