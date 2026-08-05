/// @file lib/features/workout/presentation/screens/workout_plan_screen.dart
/// @description Pantalla completa del plan de rutina con mapa anatómico interactivo,
/// PageView de ejercicios con swipe, y tarjetas de series/reps con glassmorphism.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../../core/services/index.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/workout_entities.dart';
import '../../domain/muscle_catalog.dart';
import '../widgets/interactive_anatomy_map.dart';

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

  Future<void> _updateHeaderColor(WorkoutExercise exercise) async {
    final coverUrl = exercise.videoUrl?.isNotEmpty == true
        ? exercise.videoUrl!
        : 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&q=80&w=200';
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
      );
      if (mounted) {
        setState(() {
          _headerColor = palette.dominantColor?.color ?? AppColors.neonPink;
        });
      }
    } catch (e) {
      debugPrint('Error generating palette: $e');
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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── STICKY APP BAR con nombre del plan ─────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.plan.nivel.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neonPurple,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    widget.plan.nombre,
                    style: GoogleFonts.outfit(
                      fontSize: 17,
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
                    colors: [_headerColor.withValues(alpha: 0.6), AppColors.background],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // ── TABS DE DÍAS ────────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
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
                // ── MAPA ANATÓMICO ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _currentExercises.isNotEmpty
                      ? InteractiveAnatomyMap(
                          exercises: _currentExercises,
                          initialIndex: _currentExerciseIndex,
                          height: 340,
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
      bottomNavigationBar: _MiniPlayer(
        exercise: _currentExercises.isNotEmpty ? _currentExercises[_currentExerciseIndex] : null,
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

    final coverUrl = exercise.videoUrl?.isNotEmpty == true
        ? exercise.videoUrl!
        : 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&q=80&w=200';

    return ClipRRect(
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
            // Cover Image
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 64,
                height: 64,
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.withValues(alpha: 0.2)),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.withValues(alpha: 0.2),
                    child: const Icon(Icons.fitness_center, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI-PLAYER FLOTANTE (Spotify Style)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({this.exercise, required this.onNext});
  final WorkoutExercise? exercise;
  final VoidCallback onNext;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  bool _isPlaying = true;

  @override
  Widget build(BuildContext context) {
    if (widget.exercise == null) return const SizedBox.shrink();

    final ex = widget.exercise!;
    final coverUrl = ex.videoUrl?.isNotEmpty == true
        ? ex.videoUrl!
        : 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&q=80&w=200';

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
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 40,
                height: 40,
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.withValues(alpha: 0.2)),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.withValues(alpha: 0.2),
                    child: const Icon(Icons.fitness_center, size: 20, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
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
            // Controls
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () => setState(() => _isPlaying = !_isPlaying),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
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
