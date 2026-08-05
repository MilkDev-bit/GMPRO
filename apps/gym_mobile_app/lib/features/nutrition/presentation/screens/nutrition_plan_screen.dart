/// @file lib/features/nutrition/presentation/screens/nutrition_plan_screen.dart
/// @description Pantalla principal de nutrición y macros alimentada por Open Food Facts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../providers/nutrition_provider.dart';
import '../widgets/macro_summary_dashboard.dart';
import '../widgets/meal_card.dart';

class NutritionPlanScreen extends ConsumerWidget {
  const NutritionPlanScreen({super.key, required this.plan});
  final NutritionPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nutritionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── CABECERA PEGADIZA ──────────────────────────────────────────
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
                        'PLAN NUTRICIONAL',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonCyan,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        plan.nombre,
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
                        colors: [Color(0xFF1F1A3A), AppColors.background],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.neonCyan),
                    tooltip: 'Recalcular Dieta con IA',
                    onPressed: () => ref.read(nutritionProvider.notifier).generateDietPlan(),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── CUERPO PRINCIPAL ───────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList.list(
                  children: [
                    // 1. DASHBOARD DE MACROS & HIDRATACIÓN
                    MacroSummaryDashboard(
                      plan: plan,
                      waterConsumedMl: state.waterConsumedMl,
                    ),
                    const SizedBox(height: 28),

                    // 2. TÍTULO DESGLOSE DE COMIDAS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DESGLOSE POR COMIDA',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 1.8,
                          ),
                        ),
                        Text(
                          '${plan.comidas.length} comidas diarias',
                          style: AppTypography.caption.copyWith(color: AppColors.neonCyan),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 3. TARJETAS DE COMIDA
                    ...plan.comidas.map((meal) => MealCard(meal: meal)),
                    const SizedBox(height: 20),

                    // 4. BOTÓN REAJUSTAR IA
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded, color: AppColors.neonCyan, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¿Cambió tu intensidad de entreno?',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pídele a GymBot que reajuste tus macros y alimentos según tu desgaste.',
                                  style: AppTypography.caption,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.neonCyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => ref.read(nutritionProvider.notifier).generateDietPlan(),
                            child: Text(
                              'Reajustar IA',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
