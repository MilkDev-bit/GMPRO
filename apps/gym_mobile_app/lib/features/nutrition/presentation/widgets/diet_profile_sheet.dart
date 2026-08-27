/// @file lib/features/nutrition/presentation/widgets/diet_profile_sheet.dart
/// @description Formulario para capturar los datos REALES del socio (objetivo,
/// peso, estatura, edad, actividad) y generar la dieta con la fórmula científica
/// del ai-service. Antes esos valores iban hardcodeados (75kg/175cm/25), así que
/// el plan no era personalizado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/presentation/widgets/premium_loading_overlay.dart';
import '../providers/nutrition_provider.dart';
import 'ingredient_picker_sheet.dart';

class DietProfileSheet extends ConsumerStatefulWidget {
  const DietProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const DietProfileSheet(),
    );
  }

  @override
  ConsumerState<DietProfileSheet> createState() => _DietProfileSheetState();
}

class _DietProfileSheetState extends ConsumerState<DietProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _peso;
  late final TextEditingController _estatura;
  late final TextEditingController _edad;
  // Ingredientes que el socio quiere incluir (elegidos del catálogo, por nombre).
  List<String> _ingredientes = [];
  String _objetivo = 'hipertrofia';
  String _actividad = 'moderado';
  bool _submitting = false;
  String? _error;

  static const Map<String, String> _objetivos = {
    'hipertrofia': 'Ganar músculo (hipertrofia)',
    'definicion': 'Definir / bajar grasa',
    'mantenimiento': 'Mantener',
    'fuerza': 'Fuerza',
  };
  static const Map<String, String> _actividades = {
    'sedentario': 'Sedentario',
    'moderado': 'Moderado (3-4 días)',
    'activo': 'Activo (5-6 días)',
    'muy_activo': 'Muy activo / atleta',
  };

  @override
  void initState() {
    super.initState();
    final p = ref.read(nutritionProvider).profile;
    _peso = TextEditingController(text: p.pesoKg.toStringAsFixed(0));
    _estatura = TextEditingController(text: p.estaturaCm.toStringAsFixed(0));
    _edad = TextEditingController(text: p.edad.toString());
    _ingredientes = p.ingredientes
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    _objetivo = _objetivos.containsKey(p.objetivo) ? p.objetivo : 'hipertrofia';
    _actividad = _actividades.containsKey(p.actividad) ? p.actividad : 'moderado';
  }

  @override
  void dispose() {
    _peso.dispose();
    _estatura.dispose();
    _edad.dispose();
    super.dispose();
  }

  Future<void> _pickIngredients() async {
    FocusScope.of(context).unfocus();
    final result = await showIngredientPicker(context, initial: _ingredientes);
    if (result != null && mounted) {
      setState(() => _ingredientes = result);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    // Pantalla de carga premium de IA mientras el modelo calcula (capturamos el
    // notifier ANTES del await: sigue vivo aunque el sheet se cierre).
    final overlay = ref.read(loadingOverlayProvider.notifier);
    overlay.showAiOverlay();
    // Esperamos el resultado: sólo cerramos si la generación tuvo éxito. Si falla,
    // el formulario se queda abierto mostrando el error (antes se cerraba y el
    // dashboard volvía a "completa tu perfil", pareciendo un bucle).
    await ref.read(nutritionProvider.notifier).generateDietPlan(
          objetivo: _objetivo,
          pesoKg: double.tryParse(_peso.text.trim()),
          estaturaCm: double.tryParse(_estatura.text.trim()),
          edad: int.tryParse(_edad.text.trim()),
          actividad: _actividad,
          ingredientes: _ingredientes.join(', '),
        );
    overlay.hide();
    if (!mounted) return;
    final err = ref.read(nutritionProvider).error;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _submitting = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tu plan a tu medida', style: AppTypography.titleLarge.copyWith(fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                'Con estos datos calculamos tus calorías y macros con la fórmula científica.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _label('Objetivo'),
              const SizedBox(height: 8),
              _dropdown(_objetivo, _objetivos, (v) => setState(() => _objetivo = v ?? _objetivo)),
              const SizedBox(height: 18),
              _label('Datos físicos'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _numField(_peso, 'Peso', 'kg', 30, 300)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField(_estatura, 'Estatura', 'cm', 100, 230)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField(_edad, 'Edad', 'años', 12, 100)),
                ],
              ),
              const SizedBox(height: 18),
              _label('Nivel de actividad'),
              const SizedBox(height: 8),
              _dropdown(_actividad, _actividades, (v) => setState(() => _actividad = v ?? _actividad)),

              const SizedBox(height: 18),
              _label('Ingredientes a incluir (opcional)'),
              const SizedBox(height: 8),
              _IngredientSelector(
                seleccionados: _ingredientes,
                onEdit: _pickIngredients,
                onRemove: (n) => setState(() => _ingredientes.remove(n)),
              ),
              const SizedBox(height: 6),
              Text(
                'Elige alimentos del catálogo y el plan se armará priorizándolos.',
                style: AppTypography.caption.copyWith(color: AppColors.textMuted, fontSize: 12),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTypography.bodyMedium.copyWith(color: Colors.redAccent, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 20),
                  label: Text(_submitting ? 'Generando tu plan...' : 'Generar plan con IA',
                      style: AppTypography.buttonLabel.copyWith(color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.neonCyan.withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String hint, String suffix, int min, int max) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
      decoration: _decoration(hint: hint, suffix: suffix),
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        if (n == null || n < min || n > max) return '$min–$max';
        return null;
      },
    );
  }

  Widget _dropdown(String value, Map<String, String> options, ValueChanged<String?> onChanged) {
    return InputDecorator(
      decoration: _decoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _decoration({String? hint, String? suffix}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 14),
      suffixText: suffix,
      suffixStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
      errorStyle: const TextStyle(fontSize: 10.5, height: 0.9),
      filled: true,
      fillColor: AppColors.surfaceElevated,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.neonCyan, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}

/// Selector de ingredientes: chips de lo elegido + botón para abrir el buscador.
class _IngredientSelector extends StatelessWidget {
  const _IngredientSelector({
    required this.seleccionados,
    required this.onEdit,
    required this.onRemove,
  });

  final List<String> seleccionados;
  final VoidCallback onEdit;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final emerald = AppColors.accentEmeraldOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seleccionados.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in seleccionados)
                Container(
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
                          n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                              fontSize: 13, fontWeight: FontWeight.w700, color: emerald),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onRemove(n),
                        child: Icon(Icons.close_rounded, size: 16, color: emerald),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onEdit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: emerald.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded, size: 20, color: emerald),
                const SizedBox(width: 10),
                Text(
                  seleccionados.isEmpty ? 'Seleccionar ingredientes' : 'Editar ingredientes',
                  style: AppTypography.buttonLabel.copyWith(fontSize: 14, color: emerald),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
