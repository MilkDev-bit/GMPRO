/// @file lib/features/nutrition/presentation/widgets/weight_check_banner.dart
/// @description Banner de seguimiento de peso en el plan de nutrición. Dos funciones:
///   1) RECORDATORIO: si hace >7 días (o nunca) que no te pesas, te invita a hacerlo.
///   2) REAJUSTE: si tu peso actual se aleja del peso con que se generó el plan por
///      un umbral (±2 kg), te ofrece regenerar para no sufrir descompensaciones.
/// El peso es fuente de verdad única: al registrarlo actualiza el perfil (ver
/// BodyWeightNotifier.logWeight → setProfileWeight).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../workout/presentation/providers/body_stats_provider.dart';
import '../../../workout/presentation/providers/workout_provider.dart';
import '../providers/nutrition_provider.dart';

const double _kDriftKg = 2.0;      // desviación de peso que dispara el reajuste
const int _kReminderDays = 7;      // días sin pesaje para recordar

class WeightCheckBanner extends ConsumerWidget {
  const WeightCheckBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchamos el plan (para reaccionar a regeneraciones) y el peso corporal.
    ref.watch(nutritionProvider.select((s) => s.plan));
    final weightAsync = ref.watch(bodyWeightProvider);
    final planPeso = ref.read(nutritionProvider.notifier).planPesoKg;
    final planFecha = ref.read(nutritionProvider.notifier).planFecha;

    final series = weightAsync.value;
    final latest = series?.latest;

    // ── Caso REAJUSTE: te pesaste DESPUÉS de crear el plan y el peso se desvió ───
    // (si el pesaje es anterior al plan, no hubo cambio real → no molestamos).
    final pesajeTrasPlan = latest != null && planFecha != null && latest.date.isAfter(planFecha);
    if (planPeso > 0 && latest != null && pesajeTrasPlan) {
      final drift = latest.kg - planPeso;
      if (drift.abs() >= _kDriftKg) {
        final bajo = drift < 0;
        return _Banner(
          color: AppColors.warningOf(context),
          icon: Icons.tune_rounded,
          title: 'Tu peso cambió ${drift.abs().toStringAsFixed(1)} kg',
          subtitle: bajo
              ? 'Bajaste desde que se crearon tus planes. Reajusta dieta y rutina para no estancarte.'
              : 'Subiste desde que se crearon tus planes. Reajusta dieta y rutina para seguir en objetivo.',
          actionLabel: 'Reajustar',
          onAction: () {
            HapticFeedback.mediumImpact();
            // El peso alimenta AMBOS planes (la rutina toma pesoKg del perfil de
            // dieta), así que regeneramos los dos con el peso actual.
            ref.read(nutritionProvider.notifier).generateDietPlan();
            if (ref.read(workoutProvider).plan != null) {
              ref.read(workoutProvider.notifier).generateRoutinePlan();
            }
          },
        );
      }
    }

    // ── Caso RECORDATORIO: nunca se pesó o hace >7 días ─────────────────────────
    final now = DateTime.now();
    final dias = latest == null ? null : now.difference(latest.date).inDays;
    if (latest == null || (dias != null && dias >= _kReminderDays)) {
      return _Banner(
        color: AppColors.accentCyanOf(context),
        icon: Icons.monitor_weight_outlined,
        title: latest == null ? 'Registra tu peso' : 'Han pasado $dias días sin pesarte',
        subtitle: 'Pésate cada semana para mantener tu plan calibrado a tu peso real.',
        actionLabel: 'Registrar',
        onAction: () => _logWeightDialog(context, ref, latest?.kg),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _logWeightDialog(BuildContext context, WidgetRef ref, double? actual) async {
    final controller = TextEditingController(text: actual?.toStringAsFixed(1) ?? '');
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text('Registrar peso de hoy', style: AppTypography.titleLargeOf(ctx)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: TextStyle(color: AppColors.textPrimaryOf(ctx)),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(',', '.'));
              Navigator.pop(ctx, (v != null && v > 0) ? v : null);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value != null) {
      HapticFeedback.selectionClick();
      // Registra el peso (y por la Pieza 1, actualiza el perfil automáticamente).
      await ref.read(bodyWeightProvider.notifier).logWeight(value);
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                      fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context), height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(actionLabel,
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
