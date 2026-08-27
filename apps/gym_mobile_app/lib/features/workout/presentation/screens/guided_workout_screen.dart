/// @file lib/features/workout/presentation/screens/guided_workout_screen.dart
/// @description Runner de entrenamiento guiado: abre la sesión del día, muestra el
/// objetivo pre-cargado con su "porqué", registra serie a serie, cuenta el
/// descanso y celebra los PR.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/presentation/widgets/glass_surface.dart';
import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/workout_entities.dart';
import '../../domain/training/set_log.dart';
import '../providers/guided_workout_provider.dart';

class GuidedWorkoutScreen extends ConsumerStatefulWidget {
  const GuidedWorkoutScreen({
    super.key,
    required this.day,
    this.objetivo = 'hipertrofia',
    this.routineName = 'Entrenamiento',
  });

  final WorkoutDay day;
  final String objetivo;
  final String routineName;

  @override
  ConsumerState<GuidedWorkoutScreen> createState() => _GuidedWorkoutScreenState();
}

class _GuidedWorkoutScreenState extends ConsumerState<GuidedWorkoutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(guidedWorkoutProvider.notifier).start(
            widget.day,
            objetivo: widget.objetivo,
            routineName: widget.routineName,
          );
    });
  }

  Future<void> _confirmExit() async {
    final s = ref.read(guidedWorkoutProvider);
    if (s.phase == GuidedPhase.finished || s.phase == GuidedPhase.idle) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text('¿Salir del entrenamiento?', style: AppTypography.titleLarge),
        content: Text('Se descartará la sesión en curso.', style: AppTypography.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Salir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (leave == true) {
      await ref.read(guidedWorkoutProvider.notifier).abort();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(guidedWorkoutProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.routineName, style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmExit,
          ),
        ),
        body: SafeArea(
          child: switch (s.phase) {
            GuidedPhase.idle => const Center(
                child: CircularProgressIndicator(color: AppColors.neonPink),
              ),
            GuidedPhase.finished => _FinishedView(state: s),
            GuidedPhase.resting => _RestingView(state: s),
            GuidedPhase.exercising => _ExercisingView(state: s),
          },
        ),
      ),
    );
  }
}

// ── Vista: ejercitando ────────────────────────────────────────────────────────
class _ExercisingView extends ConsumerWidget {
  const _ExercisingView({required this.state});
  final GuidedSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = state.currentExercise;
    if (ex == null) return const SizedBox.shrink();
    final notifier = ref.read(guidedWorkoutProvider.notifier);
    final isTimed = state.currentPlan!.config.kind == ExerciseKind.timed;
    final isBodyweight = state.currentPlan!.config.kind == ExerciseKind.bodyweight;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Demostración del ejercicio (GIF animado / imagen), si el catálogo la tiene.
          if (ex.coverUrl != null && ex.coverUrl!.isNotEmpty) ...[
            _ExerciseMedia(url: ex.coverUrl!),
            const SizedBox(height: 16),
          ],

          // Progreso del día.
          Text(
            'EJERCICIO ${state.exerciseIndex + 1}/${state.plans.length}',
            style: GoogleFonts.outfit(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.textMuted, letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(ex.nombre,
                    style: AppTypography.displayMedium.copyWith(fontSize: 24)),
              ),
              if (state.isCurrentPr) ...[
                const SizedBox(width: 8),
                _PrBadge(),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Objetivo + porqué.
          GlassSurface(
            borderRadius: 22,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OBJETIVO DE HOY',
                    style: GoogleFonts.outfit(
                        fontSize: 10, fontWeight: FontWeight.w800,
                        color: AppColors.accentCyanOf(context), letterSpacing: 1.8)),
                const SizedBox(height: 8),
                _SetsDots(done: state.setsDone, total: state.currentTargetSets),
                const SizedBox(height: 10),
                Text(state.currentPlan!.target.reason,
                    style: AppTypography.bodyMedium.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Steppers.
          if (isTimed)
            _Stepper(
              label: 'Tiempo (s)',
              value: '${state.currentTimeSec ?? 0}',
              onMinus: () => notifier.adjustTime(-5),
              onPlus: () => notifier.adjustTime(5),
            )
          else ...[
            if (!isBodyweight)
              _Stepper(
                label: 'Peso (kg)',
                value: (state.currentWeightKg ?? 0).toStringAsFixed(1),
                onMinus: () => notifier.adjustWeight(-2.5),
                onPlus: () => notifier.adjustWeight(2.5),
              ),
            const SizedBox(height: 14),
            _Stepper(
              label: state.currentPlan!.config.perSide ? 'Reps (total)' : 'Reps',
              value: '${state.currentReps ?? 0}'
                  '${state.currentPlan!.config.perSide && (state.currentReps ?? 0) > 0 ? '  (${(state.currentReps ?? 0) ~/ 2}/lado)' : ''}',
              onMinus: () => notifier.adjustReps(state.currentPlan!.config.perSide ? -2 : -1),
              onPlus: () => notifier.adjustReps(state.currentPlan!.config.perSide ? 2 : 1),
            ),
          ],

          const SizedBox(height: 28),

          // Registrar serie.
          Pressable(
            haptic: PressHaptic.medium,
            onTap: notifier.logCurrentSet,
            child: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Text(
                state.setsDone + 1 >= state.currentTargetSets &&
                        state.exerciseIndex >= state.plans.length - 1
                    ? 'Registrar y finalizar'
                    : 'Registrar serie ${state.setsDone + 1}',
                style: AppTypography.buttonLabel.copyWith(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vista: descanso ───────────────────────────────────────────────────────────
class _RestingView extends ConsumerWidget {
  const _RestingView({required this.state});
  final GuidedSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedWorkoutProvider.notifier);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('DESCANSO',
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: AppColors.textMuted, letterSpacing: 3)),
          const SizedBox(height: 12),
          if (state.restEndsAt != null) _RestCountdown(endsAt: state.restEndsAt!),
          const SizedBox(height: 8),
          if (state.nextExercise != null || state.setsDone < state.currentTargetSets)
            Text(
              state.setsDone < state.currentTargetSets
                  ? 'Sigue: ${state.currentExercise?.nombre ?? ''} — serie ${state.setsDone + 1}'
                  : 'Sigue: ${state.nextExercise?.nombre ?? ''}',
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 28),
          Pressable(
            haptic: PressHaptic.light,
            onTap: notifier.skipRest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5)),
              ),
              child: Text('Saltar descanso',
                  style: AppTypography.buttonLabel
                      .copyWith(color: AppColors.neonCyan, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestCountdown extends StatefulWidget {
  const _RestCountdown({required this.endsAt});
  final DateTime endsAt;

  @override
  State<_RestCountdown> createState() => _RestCountdownState();
}

class _RestCountdownState extends State<_RestCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endsAt.difference(DateTime.now()).inSeconds;
    final sec = remaining < 0 ? 0 : remaining;
    final mm = (sec ~/ 60).toString().padLeft(2, '0');
    final ss = (sec % 60).toString().padLeft(2, '0');
    return Text('$mm:$ss',
        style: AppTypography.numericHeroOf(context)
            .copyWith(fontSize: 72, color: AppColors.neonCyan));
  }
}

// ── Vista: terminado ──────────────────────────────────────────────────────────
class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.state});
  final GuidedSessionState state;

  @override
  Widget build(BuildContext context) {
    final totalSets =
        state.logged.values.fold<int>(0, (a, b) => a + b.length);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.neonEmerald, size: 72),
            const SizedBox(height: 20),
            Text('¡Sesión completada!', style: AppTypography.displayMedium),
            const SizedBox(height: 10),
            Text(
              '${state.plans.length} ejercicios · $totalSets series'
              '${state.prs.isNotEmpty ? ' · ${state.prs.length} PR' : ''}',
              style: AppTypography.bodyLarge.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            Pressable(
              haptic: PressHaptic.medium,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text('Listo',
                    style: AppTypography.buttonLabel.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Componentes ───────────────────────────────────────────────────────────────
/// Demostración del ejercicio: GIF animado (o imagen). Usa `cover` para llenar todo
/// el espacio sin barras: recorta el borde sobrante (casi siempre fondo) y deja la
/// figura centrada bien grande. Proporción 4:3, cómoda para las fotos del dataset.
class _ExerciseMedia extends StatelessWidget {
  const _ExerciseMedia({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        // Altura compacta (antes 4:3 ≈ 540px ocupaba media pantalla y empujaba el
        // botón "Registrar serie" fuera de la vista).
        height: 200,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (_, __) => Container(
            color: AppColors.darkSurfaceElevated,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonCyan),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.darkSurfaceElevated,
            alignment: Alignment.center,
            child: const Icon(Icons.fitness_center_rounded,
                color: AppColors.textMuted, size: 40),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundBtn(icon: Icons.remove_rounded, onTap: onMinus),
            SizedBox(
              width: 180,
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: AppTypography.numericHeroOf(context).copyWith(fontSize: 40)),
            ),
            _RoundBtn(icon: Icons.add_rounded, onTap: onPlus),
          ],
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.darkSurfaceElevated,
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: AppColors.neonCyan, size: 26),
      ),
    );
  }
}

class _SetsDots extends StatelessWidget {
  const _SetsDots({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i < done;
        return Container(
          margin: const EdgeInsets.only(right: 8),
          width: 26,
          height: 8,
          decoration: BoxDecoration(
            color: filled ? AppColors.neonEmerald : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _PrBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 14),
          const SizedBox(width: 4),
          Text('PR',
              style: GoogleFonts.outfit(
                  fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.warning)),
        ],
      ),
    );
  }
}
