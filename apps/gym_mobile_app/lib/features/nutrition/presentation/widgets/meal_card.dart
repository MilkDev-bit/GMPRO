/// @file lib/features/nutrition/presentation/widgets/meal_card.dart
/// @description Tarjeta con Glassmorphism para cada comida del día. Muestra macros
/// acumulados, expansión orgánica animada (SizeTransition / AnimatedCrossFade) y
/// alimentos con Swipe-to-Dismiss estilo premium y vibración háptica.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/presentation/widgets/glass_surface.dart';
import '../../../../core/presentation/widgets/pressable.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../providers/nutrition_provider.dart';
import 'food_search_modal.dart';

class MealCard extends ConsumerStatefulWidget {
  const MealCard({super.key, required this.meal});
  final Meal meal;

  @override
  ConsumerState<MealCard> createState() => _MealCardState();
}

class _MealCardState extends ConsumerState<MealCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = true;

  IconData _getMealIcon(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'desayuno':
        return Icons.wb_sunny_rounded;
      case 'almuerzo':
        return Icons.wb_twilight_rounded;
      case 'pre_entreno':
        return Icons.bolt_rounded;
      case 'cena':
        return Icons.nightlight_round;
      default:
        return Icons.restaurant_rounded;
    }
  }

  Color _getMealColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'desayuno':
        return AppColors.neonPurple;
      case 'almuerzo':
        return AppColors.neonCyan;
      case 'pre_entreno':
        return AppColors.neonPink;
      case 'cena':
        return AppColors.neonViolet;
      default:
        return AppColors.neonPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final accentColor = _getMealColor(meal.tipo);
    final icon = _getMealIcon(meal.tipo);

    // Sombra de acento animada al expandir (fuera del cristal, sin recortarse).
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: _isExpanded ? 0.18 : 0.08),
            blurRadius: _isExpanded ? 22 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // Cristal premium: blur + relleno de marca + highlight specular + borde acento.
      child: GlassSurface(
        borderRadius: 26,
        blurSigma: 14,
        specularOpacity: 0.22,
        border: Border.all(
          color: accentColor.withValues(alpha: _isExpanded ? 0.45 : 0.25),
          width: _isExpanded ? 1.5 : 1.0,
        ),
        gradient: LinearGradient(
          colors: AppColors.isDark(context)
              ? [
                  Color.lerp(const Color(0xFF1F1A3A), accentColor, 0.12)!,
                  const Color(0xFF100E22),
                ]
              : [
                  Color.lerp(AppColors.lightSurface, accentColor, 0.08)!,
                  AppColors.lightSurfaceElevated.withValues(alpha: 0.95),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
            children: [
              // ── CABECERA COMIDA CON FLECHA ANIMADA ─────────────────────────
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isExpanded = !_isExpanded);
                },
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: accentColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meal.nombre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${meal.horaSugerida}  ·  ${meal.alimentos.length} alimentos',
                              style: AppTypography.captionOf(context).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TweenAnimationBuilder<int>(
                            tween: IntTween(begin: 0, end: meal.caloriasTotal),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutExpo,
                            // Cifras tabulares: los dígitos no "tiemblan" al contar.
                            builder: (context, val, _) => Text(
                              '$val kcal',
                              style: AppTypography.numericLargeOf(context).copyWith(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: accentColor,
                              ),
                            ),
                          ),
                          Text(
                            'P:${meal.proteinasTotal}g C:${meal.carbohidratosTotal}g G:${meal.grasasTotal}g',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondaryOf(context),
                              fontFeatures: AppTypography.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0.0,
                          end: _isExpanded ? 0.5 : 0.0, // Rotación de 180 grados (0.5 de vuelta)
                        ),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutBack,
                        builder: (context, value, child) {
                          return Transform.rotate(
                            angle: value * 3.1415926535 * 2,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: accentColor,
                              size: 26,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── CUERPO CON ANIMACIÓN ORGÁNICA CROSSFADE ────────────────────
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Column(
                  children: [
                    Divider(color: AppColors.glassBorderOf(context), height: 1),
                    if (meal.alimentos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No hay alimentos asignados aún.',
                          style: AppTypography.captionOf(context),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        itemCount: meal.alimentos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = meal.alimentos[index];
                          return _FoodRowSwipeable(mealId: meal.id, comidaTipo: meal.tipo, item: item);
                        },
                      ),

                    // ── PREPARACIÓN / RECETA ─────────────────────────────────
                    if (meal.preparacion.isNotEmpty) ...[
                      Divider(color: AppColors.glassBorderOf(context), height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PREPARACIÓN',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (int i = 0; i < meal.preparacion.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.14),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          meal.preparacion[i],
                                          style: AppTypography.bodyMediumOf(context).copyWith(
                                            fontSize: 13.5,
                                            height: 1.4,
                                            color: AppColors.textSecondaryOf(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // ── BOTÓN AGREGAR ALIMENTO (OPEN FOOD FACTS) ─────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                      // Pressable: spring physics + háptica media en la acción primaria.
                      child: Pressable(
                        haptic: PressHaptic.medium,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => FoodSearchModal(mealId: meal.id),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline_rounded, color: accentColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '+ Agregar Alimento (Open Food Facts)',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
    );
  }
}

class _FoodRowSwipeable extends ConsumerWidget {
  const _FoodRowSwipeable({required this.mealId, required this.comidaTipo, required this.item});
  final String mealId;
  final String comidaTipo;
  final FoodItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consumed = ref.watch(nutritionProvider
        .select((s) => s.consumedFoodIds.containsKey(item.nombre.toLowerCase().trim())));
    return Dismissible(
      key: ValueKey('${mealId}_${item.codigoBarras}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.heavyImpact();
        ref.read(nutritionProvider.notifier).removeFoodFromMeal(mealId, item.codigoBarras);
      },
      background: Container(
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              AppColors.error.withValues(alpha: 0.35),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Desliza para eliminar',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorderOf(context)),
        ),
        child: Row(
          children: [
            // Marcar como consumido (sincroniza con el diario nutricional real).
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(nutritionProvider.notifier).toggleFoodConsumed(item, comidaTipo);
              },
              behavior: HitTestBehavior.opaque,
              child: Icon(
                consumed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: consumed ? AppColors.success : AppColors.textMutedOf(context),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            if (item.esOpenFoodFacts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'OFF',
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.success,
                  ),
                ),
              ),
            if (item.esOpenFoodFacts) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nombre,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.marca}  •  ${item.porcionG.toStringAsFixed(0)}g',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMutedOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.calorias} kcal',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'P:${item.proteinas}g C:${item.carbohidratos}g G:${item.grasas}g',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
