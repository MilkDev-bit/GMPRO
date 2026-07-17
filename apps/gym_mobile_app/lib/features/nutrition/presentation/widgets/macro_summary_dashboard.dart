/// @file lib/features/nutrition/presentation/widgets/macro_summary_dashboard.dart
/// @description Panel de control visual con Glassmorphism para calorías diarias,
/// barras de progreso animadas (TweenAnimationBuilder escalonado) con resplandor neón
/// y contador interactivo rodante de hidratación con físicas elásticas.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../providers/nutrition_provider.dart';

class MacroSummaryDashboard extends ConsumerStatefulWidget {
  const MacroSummaryDashboard({
    super.key,
    required this.plan,
    required this.waterConsumedMl,
  });

  final NutritionPlan plan;
  final int waterConsumedMl;

  @override
  ConsumerState<MacroSummaryDashboard> createState() => _MacroSummaryDashboardState();
}

class _MacroSummaryDashboardState extends ConsumerState<MacroSummaryDashboard>
    with SingleTickerProviderStateMixin {
  bool _waterWaveAnimation = false;

  void _triggerWaterPulse(int amount) {
    HapticFeedback.mediumImpact();
    ref.read(nutritionProvider.notifier).addWater(amount);
    setState(() => _waterWaveAnimation = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _waterWaveAnimation = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final calConsumidas = plan.caloriasConsumidas;
    final calMeta = plan.caloriasMeta;
    final calPercent = (calConsumidas / (calMeta > 0 ? calMeta : 1)).clamp(0.0, 1.2);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.isDark(context)
                  ? [
                      const Color(0xFF231D42).withValues(alpha: 0.88),
                      const Color(0xFF100E22).withValues(alpha: 0.96),
                    ]
                  : [
                      AppColors.lightSurface.withValues(alpha: 0.90),
                      AppColors.lightSurfaceElevated.withValues(alpha: 0.96),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: AppColors.neonPurple.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonPurple.withValues(alpha: 0.22),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── ENCABEZADO CALORÍAS CON ANIMACIÓN DE CONTEO ────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CALORÍAS DIARIAS (OPEN FOOD FACTS)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentCyanOf(context), // WCAG: texto seguro en claro/oscuro
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          TweenAnimationBuilder<int>(
                            tween: IntTween(begin: 0, end: calConsumidas),
                            duration: const Duration(milliseconds: 1200),
                            curve: Curves.easeOutExpo,
                            builder: (context, value, child) {
                              return Text(
                                '$value',
                                style: GoogleFonts.outfit(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimaryOf(context),
                                  height: 1.0,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '/ $calMeta kcal',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMutedOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: calPercent.toDouble()),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.fastOutSlowIn,
                    builder: (context, value, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.neonPurple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonPurple.withValues(alpha: 0.35),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, color: AppColors.accentPurpleOf(context), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${(value * 100).round()}%',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accentPurpleOf(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── BARRA PRINCIPAL CALORÍAS ANIMADA ───────────────────────────
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: calPercent.clamp(0.0, 1.0).toDouble()),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.fastOutSlowIn,
                builder: (context, value, child) {
                  return Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: (calConsumidas > calMeta ? AppColors.neonPink : AppColors.neonCyan)
                              .withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: AppColors.glassColorOf(context, alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          calConsumidas > calMeta ? AppColors.neonPink : AppColors.neonCyan,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Porcentaje completado respecto al objetivo del día de hoy.',
                style: AppTypography.captionOf(context).copyWith(color: AppColors.textMutedOf(context)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MacroBarAnimated(
                      label: 'Proteínas',
                      current: plan.proteinasConsumidas,
                      target: plan.proteinasMetaG.toDouble(),
                      unit: 'g',
                      color: AppColors.accentEmeraldOf(context), // WCAG-safe en claro
                      delayMs: 100,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MacroBarAnimated(
                      label: 'Carbos',
                      current: plan.carbohidratosConsumidas,
                      target: plan.carbohidratosMetaG.toDouble(),
                      unit: 'g',
                      color: AppColors.accentCyanOf(context),
                      delayMs: 250,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MacroBarAnimated(
                      label: 'Grasas',
                      current: plan.grasasConsumidas,
                      target: plan.grasasMetaG.toDouble(),
                      unit: 'g',
                      color: AppColors.accentPinkOf(context),
                      delayMs: 400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: AppColors.glassBorderOf(context), height: 1),
              const SizedBox(height: 18),

              // ── SECCIÓN HIDRATACIÓN CON ROLLING COUNTER & PULSE ────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut,
                        padding: EdgeInsets.all(_waterWaveAnimation ? 14 : 10),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: _waterWaveAnimation ? 0.35 : 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.info.withValues(alpha: _waterWaveAnimation ? 0.9 : 0.4),
                            width: _waterWaveAnimation ? 2.5 : 1.0,
                          ),
                          boxShadow: _waterWaveAnimation
                              ? [
                                  BoxShadow(
                                    color: AppColors.info.withValues(alpha: 0.6),
                                    blurRadius: 20,
                                    spreadRadius: 4,
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(Icons.water_drop_rounded, color: AppColors.infoOf(context), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HIDRATACIÓN DIARIA',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMutedOf(context),
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              TweenAnimationBuilder<int>(
                                tween: IntTween(begin: 0, end: widget.waterConsumedMl),
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.elasticOut,
                                builder: (context, value, child) {
                                  return Text(
                                    '$value',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.infoOf(context),
                                    ),
                                  );
                                },
                              ),
                              Text(
                                ' / ${plan.aguaMetaMl} ml',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _WaterQuickButtonElastic(
                        label: '+250ml',
                        onTap: () => _triggerPulse(250),
                      ),
                      const SizedBox(width: 8),
                      _WaterQuickButtonElastic(
                        label: '+500ml',
                        onTap: () => _triggerPulse(500),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerPulse(int ml) {
    _triggerWaterPulse(ml);
  }
}

class _MacroBarAnimated extends StatefulWidget {
  const _MacroBarAnimated({
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
    required this.color,
    required this.delayMs,
  });

  final String label;
  final double current;
  final double target;
  final String unit;
  final Color color;
  final int delayMs;

  @override
  State<_MacroBarAnimated> createState() => _MacroBarAnimatedState();
}

class _MacroBarAnimatedState extends State<_MacroBarAnimated> {
  bool _startAnimation = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _startAnimation = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (_startAnimation ? (widget.current / (widget.target > 0 ? widget.target : 1)) : 0.0)
        .clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: widget.color,
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: widget.current),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutExpo,
            builder: (context, value, child) {
              return Text(
                '${value.toStringAsFixed(0)} / ${widget.target.toStringAsFixed(0)}${widget.unit}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimaryOf(context),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: ratio.toDouble()),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.fastOutSlowIn,
                builder: (context, value, child) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: AppColors.glassColorOf(context, alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaterQuickButtonElastic extends StatefulWidget {
  const _WaterQuickButtonElastic({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_WaterQuickButtonElastic> createState() => _WaterQuickButtonElasticState();
}

class _WaterQuickButtonElasticState extends State<_WaterQuickButtonElastic>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque: toda el área (incluido el padding) responde al toque.
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
        // Hitbox mínima de 44x44 px lógicos (Apple HIG) para evitar toques erróneos.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.info.withValues(alpha: 0.25),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: AppColors.infoOf(context), size: 14),
                Text(
                  widget.label,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.infoOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
