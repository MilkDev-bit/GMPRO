/// @file lib/features/workout/presentation/screens/workout_plan_screen.dart
/// @description Pantalla completa del plan de rutina con mapa anatómico interactivo,
/// PageView de ejercicios con swipe, y tarjetas de series/reps con glassmorphism.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/workout_entities.dart';
import '../../domain/muscle_catalog.dart';
import '../widgets/interactive_anatomy_map.dart';
import '../providers/workout_provider.dart';

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

  WorkoutDay get _currentDay => widget.plan.dias[_currentDayIndex];
  List<WorkoutExercise> get _currentExercises => _currentDay.ejercicios;
  WorkoutExercise get _currentExercise => _currentExercises[_currentExerciseIndex];

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
    });
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
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1535), AppColors.background],
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE EJERCICIO con glassmorphism
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
    // Color del primer músculo primario
    Color accentColor = AppColors.neonPink;
    if (exercise.musculos_primarios.isNotEmpty) {
      final m = MuscleCatalog.byKey(exercise.musculos_primarios.first);
      if (m != null) accentColor = m.color;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(const Color(0xFF1A1535), accentColor, isActive ? 0.08 : 0.02)!,
                const Color(0xFF0F0D1E),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive
                  ? accentColor.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.07),
              width: isActive ? 1.5 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ]
                : [],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$exerciseNumber',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      exercise.nombre,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Series / Repeticiones / Descanso
              Row(
                children: [
                  _StatBadge(label: 'Series', value: '${exercise.series}', color: accentColor),
                  const SizedBox(width: 10),
                  _StatBadge(label: 'Reps', value: exercise.repeticiones, color: AppColors.neonCyan),
                  const SizedBox(width: 10),
                  _StatBadge(
                    label: 'Descanso',
                    value: '${exercise.descansoSeg}s',
                    color: AppColors.success,
                  ),
                ],
              ),
              if (exercise.notas != null && exercise.notas!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        exercise.notas!,
                        style: AppTypography.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
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
