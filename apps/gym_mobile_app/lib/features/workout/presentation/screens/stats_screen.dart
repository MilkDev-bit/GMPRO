/// @file lib/features/workout/presentation/screens/stats_screen.dart
/// @description Pantalla de estadísticas (port de openGym): peso corporal con línea
/// de meta y heatmap de actividad. Registrar peso y fijar meta desde diálogos.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/body/body_weight.dart';
import '../providers/body_stats_provider.dart';
import '../widgets/activity_heatmap_widget.dart';
import '../widgets/body_weight_chart.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weightAsync = ref.watch(bodyWeightProvider);
    final heatmapAsync = ref.watch(activityHeatmapProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Estadísticas', style: AppTypography.titleLarge),
      ),
      body: RefreshIndicator(
        color: AppColors.neonCyan,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async {
          ref.invalidate(activityHeatmapProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── PESO CORPORAL ─────────────────────────────────────────────
            weightAsync.when(
              loading: () => const SizedBox(
                  height: 240, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('No se pudo cargar el peso: $e',
                  style: AppTypography.bodyMedium),
              data: (series) => Column(
                children: [
                  BodyWeightChart(series: series),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionChip(
                          icon: Icons.add_rounded,
                          label: 'Registrar peso',
                          onTap: () => _logWeightDialog(context, ref, series),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionChip(
                          icon: Icons.flag_rounded,
                          label: series.goalKg == null ? 'Fijar meta' : 'Editar meta',
                          onTap: () => _goalDialog(context, ref, series),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── ACTIVIDAD ─────────────────────────────────────────────────
            heatmapAsync.when(
              loading: () => const SizedBox(
                  height: 160, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('No se pudo cargar la actividad: $e',
                  style: AppTypography.bodyMedium),
              data: (hm) => ActivityHeatmapWidget(heatmap: hm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logWeightDialog(
      BuildContext context, WidgetRef ref, WeightSeries series) async {
    final controller = TextEditingController(
      text: series.latest?.kg.toStringAsFixed(1) ?? '',
    );
    final value = await _numberDialog(
      context,
      title: 'Registrar peso de hoy',
      controller: controller,
      suffix: 'kg',
    );
    if (value != null) {
      HapticFeedback.mediumImpact();
      await ref.read(bodyWeightProvider.notifier).logWeight(value);
    }
  }

  Future<void> _goalDialog(
      BuildContext context, WidgetRef ref, WeightSeries series) async {
    final controller = TextEditingController(
      text: series.goalKg?.toStringAsFixed(1) ?? '',
    );
    final value = await _numberDialog(
      context,
      title: 'Meta de peso',
      controller: controller,
      suffix: 'kg',
      allowClear: series.goalKg != null,
      onClear: () => ref.read(bodyWeightProvider.notifier).setGoal(null),
    );
    if (value != null) {
      HapticFeedback.selectionClick();
      await ref.read(bodyWeightProvider.notifier).setGoal(value);
    }
  }

  Future<double?> _numberDialog(
    BuildContext context, {
    required String title,
    required TextEditingController controller,
    required String suffix,
    bool allowClear = false,
    VoidCallback? onClear,
  }) {
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text(title, style: AppTypography.titleLarge),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: TextStyle(color: AppColors.textPrimaryOf(ctx)),
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          if (allowClear)
            TextButton(
              onPressed: () {
                onClear?.call();
                Navigator.pop(ctx);
              },
              child: Text('Quitar', style: TextStyle(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
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
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accentCyanOf(context), size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: AppTypography.buttonLabel.copyWith(
                    color: AppColors.accentCyanOf(context), fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
