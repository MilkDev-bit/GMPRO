import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../nutrition/presentation/providers/nutrition_provider.dart';
import '../../../nutrition/presentation/widgets/diet_profile_sheet.dart';

class MacroProgressCard extends ConsumerStatefulWidget {
  const MacroProgressCard({super.key});

  @override
  ConsumerState<MacroProgressCard> createState() => _MacroProgressCardState();
}

class _MacroProgressCardState extends ConsumerState<MacroProgressCard>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  late final AnimationController _progressController;
  late final Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _progressAnim = CurvedAnimation(parent: _progressController, curve: Curves.easeOutCubic);

    Future.microtask(() {
      if (!mounted) return;
      _entryController.forward();
      _progressController.forward();
      // Ya NO autogeneramos con defaults: el usuario genera su plan con datos
      // reales desde el formulario (ver estado "completa tu perfil" abajo).
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nutritionState = ref.watch(nutritionProvider);
    final plan = nutritionState.plan;

    if (plan == null) {
      // Generando: spinner. Sin plan aún: invitación a completar el perfil.
      if (nutritionState.isLoading) {
        return Container(
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFF232323),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
        );
      }
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu_rounded, color: AppColors.neonCyan, size: 40),
            const SizedBox(height: 12),
            Text(
              'Completa tu perfil',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Dinos tu peso, estatura, edad y objetivo para calcular tu plan con la fórmula científica.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: Colors.white54),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('Generar mi plan',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonCyan,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => DietProfileSheet.show(context),
              ),
            ),
          ],
        ),
      );
    }

    final int consumed = plan.caloriasConsumidas;
    final int goal = plan.caloriasMeta;
    final int remaining = (goal - consumed).clamp(0, goal);
    final double caloriesProgress = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;

    String formatDateSpanish(DateTime date) {
      const weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final weekday = weekdays[date.weekday - 1];
      final month = months[date.month - 1];
      return '$weekday ${date.day} de $month, ${date.year}';
    }
    final String todayDate = formatDateSpanish(DateTime.now());

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          // Fondo oscuro plano tipo tarjeta (reference image style)
          decoration: BoxDecoration(
            color: const Color(0xFF232323),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                child: Column(
                  children: [
                    // --- Header: Summary & Date ---
                    Text(
                      'Resumen',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      todayDate,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- Central Circle for Calories ---
                    AnimatedBuilder(
                      animation: _progressAnim,
                      builder: (context, _) => SizedBox(
                        width: 200,
                        height: 200,
                        child: CustomPaint(
                          painter: _SingleRingPainter(
                            progress: caloriesProgress * _progressAnim.value,
                            progressColor: AppColors.neonCyan, // Mantenemos neonCyan para estética GymPro
                            trackColor: const Color(0xFF383838),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$consumed / $goal',
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tu meta',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // --- Small Macro Circles ---
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _MacroSmallCircle(
                          label: 'Proteínas',
                          consumed: plan.proteinasConsumidas.toInt(),
                          goal: plan.proteinasMetaG,
                          color: AppColors.neonCyan,
                          animValue: _progressAnim.value,
                        ),
                        _MacroSmallCircle(
                          label: 'Carbos',
                          consumed: plan.carbohidratosConsumidas.toInt(),
                          goal: plan.carbohidratosMetaG,
                          color: AppColors.neonPink,
                          animValue: _progressAnim.value,
                        ),
                        _MacroSmallCircle(
                          label: 'Grasas',
                          consumed: plan.grasasConsumidas.toInt(),
                          goal: plan.grasasMetaG,
                          color: const Color(0xFFFFB300), // Amarillo neón para grasas
                          animValue: _progressAnim.value,
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),

              // --- Bottom Split Container (Consumed / Remaining) ---
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 90,
                        color: AppColors.neonPurple, // Morado del UI
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$consumed',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Consumidas',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 90,
                        color: Colors.white,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$remaining',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF232323),
                              ),
                            ),
                            Text(
                              'Restantes',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF232323).withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PEQUEÑOS CÍRCULOS DE MACROS (Protein, Carbs, Fats)
// ─────────────────────────────────────────────────────────────────────────────
class _MacroSmallCircle extends StatelessWidget {
  const _MacroSmallCircle({
    required this.label,
    required this.consumed,
    required this.goal,
    required this.color,
    required this.animValue,
  });

  final String label;
  final int consumed;
  final int goal;
  final Color color;
  final double animValue;

  @override
  Widget build(BuildContext context) {
    final double progress = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CustomPaint(
            painter: _SingleRingPainter(
              progress: progress * animValue,
              progressColor: color,
              trackColor: const Color(0xFF383838),
              strokeWidth: 4.0,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${consumed}g / ${goal}g',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER PARA UN SOLO ANILLO (Tipo Donut Chart)
// ─────────────────────────────────────────────────────────────────────────────
class _SingleRingPainter extends CustomPainter {
  const _SingleRingPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    this.strokeWidth = 14.0,
  });

  final double progress;
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - (strokeWidth / 2);

    // Fondo (Track completo)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progreso
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SingleRingPainter old) {
    return old.progress != progress ||
           old.progressColor != progressColor ||
           old.trackColor != trackColor;
  }
}
