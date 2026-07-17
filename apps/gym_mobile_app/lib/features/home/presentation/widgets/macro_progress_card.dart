/// @file lib/features/home/presentation/widgets/macro_progress_card.dart
/// @description Tarjeta de progreso de macronutrientes diarios (Proteínas, Carbos, Grasas).
/// Usa círculos de progreso concéntricos con gradientes neón y animaciones al montar.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

// ── Datos de macro (en una app real vendrían del AI/Nutrition provider) ──────
const _kMacros = [
  _MacroData(label: 'Proteínas', value: 0.72, current: 108, goal: 150, color: Color(0xFFFF007A), unit: 'g'),
  _MacroData(label: 'Carbohidratos', value: 0.55, current: 138, goal: 250, color: Color(0xFF00F0FF), unit: 'g'),
  _MacroData(label: 'Grasas', value: 0.40, current: 28, goal: 70, color: Color(0xFFFF9500), unit: 'g'),
];

class MacroProgressCard extends StatefulWidget {
  const MacroProgressCard({super.key});

  @override
  State<MacroProgressCard> createState() => _MacroProgressCardState();
}

class _MacroProgressCardState extends State<MacroProgressCard>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _kMacros.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 900 + i * 180),
      ),
    );
    _anims = _controllers
        .asMap()
        .entries
        .map((e) => Tween<double>(begin: 0, end: _kMacros[e.key].value)
            .animate(CurvedAnimation(parent: e.value, curve: Curves.easeOutCubic)))
        .toList();

    // Stagger de entrada
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: 200 + i * 120), () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1833), Color(0xFF110E21)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x22FFFFFF), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la tarjeta
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.neonPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.neonPink.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.neonPink, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '2,140 kcal restantes',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.neonPink,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Hoy',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Círculos de progreso concéntricos centrados + barras laterales
          Row(
            children: [
              // Anillo concéntrico principal (Calorías totales)
              SizedBox(
                width: 110,
                height: 110,
                child: AnimatedBuilder(
                  animation: _controllers[0],
                  builder: (context, _) => CustomPaint(
                    painter: _ConcentricRingsPainter(
                      progresses: _anims.map((a) => a.value).toList(),
                      colors: _kMacros.map((m) => m.color).toList(),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '67%',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Total',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              // Barras lineales de cada macro
              Expanded(
                child: Column(
                  children: List.generate(_kMacros.length, (i) {
                    final macro = _kMacros[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AnimatedBuilder(
                        animation: _anims[i],
                        builder: (context, _) => _MacroLinearBar(
                          macro: macro,
                          animValue: _anims[i].value,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA LINEAL DE MACRO INDIVIDUAL
// ─────────────────────────────────────────────────────────────────────────────
class _MacroLinearBar extends StatelessWidget {
  const _MacroLinearBar({required this.macro, required this.animValue});
  final _MacroData macro;
  final double animValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: macro.color,
                boxShadow: [
                  BoxShadow(
                    color: macro.color.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              macro.label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${macro.current}/${macro.goal}${macro.unit}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              // Track
              Container(
                height: 6,
                color: const Color(0xFF1E1B38),
              ),
              // Progreso
              FractionallySizedBox(
                widthFactor: animValue.clamp(0.0, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        macro.color.withValues(alpha: 0.7),
                        macro.color,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: macro.color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER PARA ANILLOS CONCÉNTRICOS
// ─────────────────────────────────────────────────────────────────────────────
class _ConcentricRingsPainter extends CustomPainter {
  const _ConcentricRingsPainter({
    required this.progresses,
    required this.colors,
  });

  final List<double> progresses;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 4;
    const trackWidth = 9.0;
    const gap = 4.0;

    for (var i = 0; i < progresses.length; i++) {
      final radius = baseRadius - i * (trackWidth + gap);
      final color = colors[i];

      // Track de fondo
      final trackPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, radius, trackPaint);

      // Arco de progreso
      if (progresses[i] > 0) {
        final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi * progresses[i],
          colors: [
            color.withValues(alpha: 0.7),
            color,
          ],
          tileMode: TileMode.clamp,
        ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          2 * math.pi * progresses[i],
          false,
          progressPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConcentricRingsPainter old) =>
      old.progresses != progresses;
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELO DE DATOS
// ─────────────────────────────────────────────────────────────────────────────
class _MacroData {
  const _MacroData({
    required this.label,
    required this.value,
    required this.current,
    required this.goal,
    required this.color,
    required this.unit,
  });

  final String label;
  final double value; // 0.0 — 1.0
  final int current;
  final int goal;
  final Color color;
  final String unit;
}
