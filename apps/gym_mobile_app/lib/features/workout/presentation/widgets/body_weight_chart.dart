/// @file lib/features/workout/presentation/widgets/body_weight_chart.dart
/// @description Gráfica de peso corporal con LÍNEA DE META (fl_chart). Cada punto
/// se colorea según si el cambio acerca (esmeralda) o aleja (rosa) de la meta.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/glass_surface.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/body/body_weight.dart';

class BodyWeightChart extends StatelessWidget {
  const BodyWeightChart({super.key, required this.series, this.height = 240});

  final WeightSeries series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentCyanOf(context);

    // Solo mostramos el placeholder si NO hay NADA que dibujar (ni pesos ni meta).
    // Con 1 solo peso ya pintamos el punto, y la meta se dibuja aunque no haya pesos.
    if (series.entries.isEmpty && series.goalKg == null) {
      return GlassSurface(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          height: height - 48,
          child: Center(
            child: Text(
              'Registra tu peso y fija una meta\npara empezar a ver tu progreso.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    // Rango vertical con margen, robusto para 0/1 puntos e incluyendo la meta.
    final hasEntries = series.entries.isNotEmpty;
    double lo = hasEntries ? series.minKg : series.goalKg!;
    double hi = hasEntries ? series.maxKg : series.goalKg!;
    if (series.goalKg != null) {
      lo = lo < series.goalKg! ? lo : series.goalKg!;
      hi = hi > series.goalKg! ? hi : series.goalKg!;
    }
    final minY = (lo - 2).floorToDouble();
    final maxY = (hi + 2).ceilToDouble();

    final spots = <FlSpot>[
      for (int i = 0; i < series.entries.length; i++)
        FlSpot(i.toDouble(), series.entries[i].kg),
    ];

    // Con 0/1 puntos damos un rango X mínimo para que el punto/meta se vean
    // centrados y el grid se dibuje (fl_chart no infiere rango sin ≥2 spots).
    final n = series.entries.length;
    final minX = n <= 1 ? -0.5 : 0.0;
    final maxX = n <= 1 ? 0.5 : (n - 1).toDouble();

    return GlassSurface(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(12, 20, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Row(
              children: [
                Text('PESO CORPORAL',
                    style: AppTypography.captionOf(context).copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 1.6, color: accent)),
                const Spacer(),
                if (series.remainingToGoalKg != null)
                  Text(
                    _goalHint(series.remainingToGoalKg!),
                    style: AppTypography.captionOf(context).copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.textSecondaryOf(context)),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: height,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.white.withValues(alpha: 0.06), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}',
                          style: AppTypography.captionOf(context)
                              .copyWith(fontSize: 10, color: AppColors.textMuted)),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (series.goalKg != null)
                      HorizontalLine(
                        y: series.goalKg!,
                        color: AppColors.neonEmerald.withValues(alpha: 0.85),
                        strokeWidth: 1.5,
                        dashArray: const [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: AppTypography.captionOf(context).copyWith(
                              color: AppColors.neonEmerald, fontWeight: FontWeight.w800),
                          labelResolver: (_) => 'Meta ${series.goalKg!.toStringAsFixed(1)} kg',
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: accent,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, i) {
                        final dir = series.deltaAt(i).direction;
                        final c = switch (dir) {
                          WeightTrendDirection.towardGoal => AppColors.neonEmerald,
                          WeightTrendDirection.awayFromGoal => AppColors.neonPink,
                          WeightTrendDirection.neutral => accent,
                        };
                        return FlDotCirclePainter(
                            radius: 3.5, color: c, strokeWidth: 0, strokeColor: c);
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.18),
                          accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _goalHint(double remaining) {
    if (remaining.abs() < 0.05) return 'En tu meta';
    return remaining < 0
        ? 'Faltan ${(-remaining).toStringAsFixed(1)} kg por bajar'
        : 'Faltan ${remaining.toStringAsFixed(1)} kg por subir';
  }
}
