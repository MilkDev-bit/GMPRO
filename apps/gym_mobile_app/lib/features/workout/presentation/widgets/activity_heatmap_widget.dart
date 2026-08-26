/// @file lib/features/workout/presentation/widgets/activity_heatmap_widget.dart
/// @description Heatmap de actividad estilo GitHub (CustomPainter). Columnas =
/// semanas, filas = 7 días; el tono neón esmeralda crece con los minutos entrenados.

import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/glass_surface.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/body/activity_heatmap.dart';

class ActivityHeatmapWidget extends StatelessWidget {
  const ActivityHeatmapWidget({super.key, required this.heatmap, this.cell = 13, this.gap = 3});

  final Heatmap heatmap;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final gridHeight = 7 * (cell + gap);
    final gridWidth = heatmap.weeks.length * (cell + gap);

    return GlassSurface(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ACTIVIDAD',
                  style: AppTypography.captionOf(context).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: AppColors.accentEmeraldOf(context))),
              const Spacer(),
              Text('${heatmap.activeDays} días · ${heatmap.totalMinutes} min',
                  style: AppTypography.captionOf(context).copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryOf(context))),
            ],
          ),
          const SizedBox(height: 14),
          // Un año no cabe: scroll horizontal, con las semanas más recientes al final.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(gridWidth, gridHeight),
                painter: _HeatmapPainter(heatmap: heatmap, cell: cell, gap: gap),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Legend(),
        ],
      ),
    );
  }
}

/// Colores por nivel de intensidad (0..4).
Color heatColorForLevel(int level) {
  switch (level) {
    case 1:
      return AppColors.neonEmerald.withValues(alpha: 0.28);
    case 2:
      return AppColors.neonEmerald.withValues(alpha: 0.50);
    case 3:
      return AppColors.neonEmerald.withValues(alpha: 0.75);
    case 4:
      return AppColors.neonEmerald;
    default:
      return Colors.white.withValues(alpha: 0.05);
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.heatmap, required this.cell, required this.gap});

  final Heatmap heatmap;
  final double cell;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = Radius.circular(cell * 0.28);

    for (int w = 0; w < heatmap.weeks.length; w++) {
      final week = heatmap.weeks[w];
      for (int d = 0; d < week.length; d++) {
        final c = week[d];
        // Celdas de relleno fuera de rango: casi invisibles.
        paint.color = c.inRange
            ? heatColorForLevel(c.level)
            : Colors.white.withValues(alpha: 0.02);
        final rect = Rect.fromLTWH(
          w * (cell + gap),
          d * (cell + gap),
          cell,
          cell,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.heatmap != heatmap || old.cell != cell || old.gap != gap;
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Menos ',
            style: AppTypography.captionOf(context)
                .copyWith(fontSize: 10, color: AppColors.textMuted)),
        for (int l = 0; l <= 4; l++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: heatColorForLevel(l),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        Text(' Más',
            style: AppTypography.captionOf(context)
                .copyWith(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }
}
