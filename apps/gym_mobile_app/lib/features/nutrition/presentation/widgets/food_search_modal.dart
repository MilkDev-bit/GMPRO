/// @file lib/features/nutrition/presentation/widgets/food_search_modal.dart
/// @description BottomSheet interactivo para buscar alimentos en Open Food Facts
/// con DraggableScrollableSheet, BackdropFilter de cristal y ajustador de porciones
/// reactivo con AnimatedSwitcher, AnimatedScale y vibración háptica.

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../providers/nutrition_provider.dart';

class FoodSearchModal extends ConsumerStatefulWidget {
  const FoodSearchModal({
    super.key,
    this.mealId,
    this.onFoodChosen,
    this.confirmLabel = 'Confirmar y Agregar a Comida',
  });

  /// Comida a la que se agrega (modo normal). null en modo "extra/antojo".
  final String? mealId;

  /// Si se provee, se llama con el alimento elegido EN VEZ de agregarlo a una
  /// comida del plan (para registrar antojos/extras). Tiene prioridad sobre mealId.
  final void Function(FoodItem food)? onFoodChosen;
  final String confirmLabel;

  @override
  ConsumerState<FoodSearchModal> createState() => _FoodSearchModalState();
}

class _FoodSearchModalState extends ConsumerState<FoodSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  FoodItem? _selectedItem;
  double _portionGrams = 100.0;

  // Micro-interacción: escala amortiguada que "late" al recalcular en tiempo real.
  double _valuePulse = 1.0;
  Timer? _pulseResetTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nutritionProvider.notifier).searchOpenFoodFacts('');
    });
  }

  @override
  void dispose() {
    _pulseResetTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Dispara un pulso de escala amortiguado (overshoot con easeOutBack) que se
  /// resuelve solo tras ~120ms, dando sensación física al recalculado.
  void _triggerValuePulse() {
    if (_valuePulse != 1.12) setState(() => _valuePulse = 1.12);
    _pulseResetTimer?.cancel();
    _pulseResetTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _valuePulse = 1.0);
    });
  }

  /// Aplica un nuevo gramaje con háptica + pulso SOLO cuando cambia el paso
  /// numérico (evita spam de vibración durante el arrastre continuo).
  void _applyPortion(double grams, {bool strongHaptic = false}) {
    final changedStep = grams.round() != _portionGrams.round();
    if (changedStep) {
      strongHaptic
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact();
      _triggerValuePulse();
    }
    setState(() => _portionGrams = grams);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nutritionProvider);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.isDark(context)
                    ? [
                        const Color(0xFF1E1836).withValues(alpha: 0.94),
                        const Color(0xFF100E22).withValues(alpha: 0.98),
                      ]
                    : [
                        AppColors.lightSurface.withValues(alpha: 0.94),
                        AppColors.lightSurfaceElevated.withValues(alpha: 0.98),
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              border: Border.all(color: AppColors.neonPurpleOf(context).withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonPurple.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── BARRA DE ARRASTRE Y TÍTULO ─────────────────────────────────
                Center(
                  child: Container(
                    width: 52,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CATÁLOGO OPEN FOOD FACTS',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonCyan,
                        letterSpacing: 1.4,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── CAMPO DE BÚSQUEDA ──────────────────────────────────────────
                TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: 'Buscar alimento por código de barras o nombre...',
                    hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.neonCyanOf(context)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _searchController.clear();
                              ref.read(nutritionProvider.notifier).searchOpenFoodFacts('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => ref.read(nutritionProvider.notifier).searchOpenFoodFacts(val),
                ),
                const SizedBox(height: 16),

                // ── CUERPO: CONFIGURADOR O LISTA DE RESULTADOS ─────────────────
                if (_selectedItem != null) ...[
                  _buildPortionConfigurator(context),
                ] else ...[
                  Expanded(
                    child: state.isSearching
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.neonCyan),
                          )
                        : state.searchResults.isEmpty
                            ? Center(
                                child: Text(
                                  'No se encontraron alimentos compatibles.',
                                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                physics: const BouncingScrollPhysics(),
                                itemCount: state.searchResults.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = state.searchResults[index];
                                  return _buildSearchResultCard(item);
                                },
                              ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultCard(FoodItem item) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedItem = item;
          _portionGrams = item.porcionG;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorderOf(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.neonCyanOf(context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.neonCyanOf(context).withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.qr_code_scanner_rounded, color: AppColors.neonCyanOf(context), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.nombre,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      if (item.esOpenFoodFacts)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Marca: ${item.marca}  •  Porción 100g: ${item.calorias100g.round()} kcal',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'P:${item.proteinas100g}g  •  C:${item.carbohidratos100g}g  •  G:${item.grasas100g}g',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.neonCyan),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPortionConfigurator(BuildContext context) {
    final customized = _selectedItem!.copyWith(porcionG: _portionGrams);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimaryOf(context)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedItem = null);
                },
              ),
              Text(
                'Ajustar Porción en Gramos',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedOf(context),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.neonPurpleOf(context).withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonPurpleOf(context).withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  customized.nombre,
                  style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textPrimaryOf(context)),
                  textAlign: TextAlign.center,
                ),
                Text(customized.marca, style: AppTypography.captionOf(context)),
                const SizedBox(height: 20),
                // Micro-escala amortiguada: el gramaje "rebota" con cada paso.
                AnimatedScale(
                  scale: _valuePulse,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutBack,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                    child: Text(
                      '${_portionGrams.round()}g',
                      key: ValueKey(_portionGrams.round()),
                      style: GoogleFonts.outfit(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonCyanOf(context),
                      ),
                    ),
                  ),
                ),
                Slider(
                  value: _portionGrams,
                  min: 10,
                  max: 500,
                  divisions: 49,
                  activeColor: AppColors.neonCyanOf(context),
                  inactiveColor: AppColors.glassBorderOf(context),
                  // Háptica ligera real + pulso por cada paso de 10g (no por pixel).
                  onChanged: (v) => _applyPortion(v),
                ),
                Wrap(
                  spacing: 10,
                  children: [50, 100, 150, 200, 250].map((g) {
                    return ChoiceChip(
                      label: Text('${g}g'),
                      selected: _portionGrams == g.toDouble(),
                      selectedColor: AppColors.neonPurpleOf(context),
                      labelStyle: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        color: _portionGrams == g.toDouble() ? Colors.white : AppColors.textMutedOf(context),
                      ),
                      onSelected: (_) => _applyPortion(g.toDouble(), strongHaptic: true),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                Divider(color: AppColors.glassBorderOf(context)),
                const SizedBox(height: 14),
                // El bloque de macros recalculado comparte el mismo pulso físico.
                AnimatedScale(
                  scale: _valuePulse,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutBack,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MacroBadgeReactive(label: 'Calorías', val: '${customized.calorias} kcal', color: AppColors.neonCyanOf(context)),
                      _MacroBadgeReactive(label: 'Proteínas', val: '${customized.proteinas}g', color: AppColors.neonEmeraldOf(context)),
                      _MacroBadgeReactive(label: 'Carbos', val: '${customized.carbohidratos}g', color: AppColors.neonPurple),
                      _MacroBadgeReactive(label: 'Grasas', val: '${customized.grasas}g', color: AppColors.neonPink),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_rounded, size: 22),
              label: Text(
                widget.confirmLabel,
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 12,
                shadowColor: AppColors.neonPurple.withValues(alpha: 0.5),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                if (widget.onFoodChosen != null) {
                  widget.onFoodChosen!(customized);
                } else if (widget.mealId != null) {
                  ref.read(nutritionProvider.notifier).addFoodToMeal(widget.mealId!, customized);
                }
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroBadgeReactive extends StatelessWidget {
  const _MacroBadgeReactive({required this.label, required this.val, required this.color});
  final String label;
  final String val;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Text(
            val,
            key: ValueKey(val),
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: color),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
