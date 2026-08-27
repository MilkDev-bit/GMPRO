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
import '../widgets/diet_profile_sheet.dart';
import '../widgets/food_search_modal.dart';
import '../widgets/weight_check_banner.dart';

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
          // SafeArea(top) para que "PLAN NUTRICIONAL" no quede bajo el notch.
          SafeArea(
            bottom: false,
            child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── CABECERA PEGADIZA ──────────────────────────────────────────
              SliverAppBar(
                primary: false,
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
                        'NUTRICIÓN · ${plan.objetivo}'.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          height: 1.0,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonCyan,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Plan semanal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 21,
                          height: 1.0,
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
                    onPressed: () => DietProfileSheet.show(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── CUERPO PRINCIPAL ───────────────────────────────────────────
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 120 + MediaQuery.of(context).padding.bottom),
                sliver: SliverList.list(
                  children: [
                    // 0. SEGUIMIENTO DE PESO (recordatorio / reajuste por drift)
                    const WeightCheckBanner(),

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
                    const SizedBox(height: 16),

                    // 3.5 REGISTRAR ANTOJO / EXTRA (algo fuera del plan)
                    _AntojoButton(onTap: () => _registrarAntojo(context, ref)),
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
                            onPressed: () => DietProfileSheet.show(context),
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
          ),
        ],
      ),
    );
  }

  /// Abre el buscador en modo "extra": registra un antojo fuera del plan y lo suma
  /// al consumo del día, sin ensuciar las comidas planificadas.
  void _registrarAntojo(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FoodSearchModal(
        confirmLabel: 'Registrar antojo',
        onFoodChosen: (food) {
          ref.read(nutritionProvider.notifier).logExtraFood(food);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Antojo registrado: ${food.nombre}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }
}

class _AntojoButton extends StatelessWidget {
  const _AntojoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.warningOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: amber.withValues(alpha: 0.40), width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.local_pizza_outlined, color: amber, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Registrar antojo / extra',
                      style: GoogleFonts.outfit(
                          fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Algo fuera del plan que comiste hoy',
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_rounded, color: amber, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
