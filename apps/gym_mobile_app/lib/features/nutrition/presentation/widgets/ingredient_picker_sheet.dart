/// @file lib/features/nutrition/presentation/widgets/ingredient_picker_sheet.dart
/// @description Selector multi-selección de ingredientes: busca en el catálogo
/// (Open Food Facts, reutilizando searchOpenFoodFacts) y el socio va marcando los
/// alimentos que quiere que su plan de dieta incluya. Devuelve la lista de nombres.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/nutrition_provider.dart';

/// Abre el selector y devuelve la lista final de ingredientes (o null si se cancela).
Future<List<String>?> showIngredientPicker(
  BuildContext context, {
  required List<String> initial,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => IngredientPickerSheet(initial: initial),
  );
}

class IngredientPickerSheet extends ConsumerStatefulWidget {
  const IngredientPickerSheet({super.key, required this.initial});
  final List<String> initial;

  @override
  ConsumerState<IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

class _IngredientPickerSheetState extends ConsumerState<IngredientPickerSheet> {
  final _searchController = TextEditingController();
  // Selección por NOMBRE (clave insensible a mayúsculas/espacios).
  late final Map<String, String> _selected; // key normalizada → nombre mostrado
  Timer? _debounce;

  String _key(String s) => s.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _selected = {for (final n in widget.initial) _key(n): n};
    // Sugerencias iniciales (mismo comportamiento que el buscador de alimentos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nutritionProvider.notifier).searchOpenFoodFacts('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(nutritionProvider.notifier).searchOpenFoodFacts(q);
    });
  }

  void _toggle(String nombre) {
    final k = _key(nombre);
    setState(() {
      if (_selected.containsKey(k)) {
        _selected.remove(k);
      } else {
        _selected[k] = nombre.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nutritionProvider);
    final emerald = AppColors.accentEmeraldOf(context);
    final results = state.searchResults;

    // Alto del teclado: se lo pasamos a la lista de resultados como padding inferior,
    // así los ítems que matchean nunca quedan tapados por el teclado.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorderOf(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ingredientes para tu plan',
                          style: AppTypography.titleLargeOf(context).copyWith(fontSize: 18),
                        ),
                      ),
                      Text(
                        '${_selected.length}',
                        style: AppTypography.numericMediumOf(context)
                            .copyWith(fontSize: 16, color: emerald),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Buscador ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevatedOf(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(Icons.search_rounded,
                            size: 20, color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onQueryChanged,
                            cursorColor: emerald,
                            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Buscar alimento (pollo, arroz, avena...)',
                              hintStyle: TextStyle(
                                  color: AppColors.textMutedOf(context), fontSize: 14),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: AppColors.textSecondaryOf(context)),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(nutritionProvider.notifier).searchOpenFoodFacts('');
                            },
                          )
                        else
                          const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),

                // ── Chips seleccionados ─────────────────────────────────────
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: ConstrainedBox(
                      // Tope de alto + scroll: aunque elijas muchos ingredientes, los
                      // chips no empujan la lista ni provocan overflow con el teclado.
                      constraints: const BoxConstraints(maxHeight: 76),
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selected.values
                                .map((n) => _SelectedChip(label: n, onRemove: () => _toggle(n)))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Resultados ──────────────────────────────────────────────
                Expanded(
                  child: state.isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : results.isEmpty
                          ? Center(
                              child: Text('Sin resultados',
                                  style: AppTypography.bodyMediumOf(context).copyWith(
                                      color: AppColors.textMutedOf(context))),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + keyboard),
                              itemCount: results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final item = results[i];
                                final checked = _selected.containsKey(_key(item.nombre));
                                return _ResultRow(
                                  nombre: item.nombre,
                                  subtitle: '${item.marca} · ${item.calorias100g.round()} kcal/100g',
                                  checked: checked,
                                  onTap: () => _toggle(item.nombre),
                                );
                              },
                            ),
                ),

                // ── Confirmar ───────────────────────────────────────────────
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: Pressable(
                      haptic: PressHaptic.medium,
                      onTap: () => Navigator.of(context).pop(_selected.values.toList()),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _selected.isEmpty
                              ? 'Listo'
                              : 'Usar ${_selected.length} ingrediente${_selected.length == 1 ? '' : 's'}',
                          style: AppTypography.buttonLabel
                              .copyWith(color: Colors.white, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: emerald.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: emerald.withValues(alpha: 0.40), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionOf(context)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: emerald),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: emerald),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.nombre,
    required this.subtitle,
    required this.checked,
    required this.onTap,
  });
  final String nombre;
  final String subtitle;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: checked ? emerald.withValues(alpha: 0.08) : AppColors.surfaceElevatedOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: checked ? emerald.withValues(alpha: 0.40) : AppColors.glassBorderOf(context),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.buttonLabelOf(context).copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionOf(context)
                        .copyWith(fontSize: 12, color: AppColors.textMutedOf(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? emerald : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: checked ? emerald : AppColors.textMutedOf(context),
                  width: 2,
                ),
              ),
              child: checked
                  ? Icon(Icons.check_rounded, size: 16, color: AppColors.surfaceOf(context))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
