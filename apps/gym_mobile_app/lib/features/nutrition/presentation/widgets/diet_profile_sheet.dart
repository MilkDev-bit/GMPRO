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
import '../providers/nutrition_provider.dart';

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
  String _objetivo = 'hipertrofia';
  String _actividad = 'moderado';

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

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    ref.read(nutritionProvider.notifier).generateDietPlan(
          objetivo: _objetivo,
          pesoKg: double.tryParse(_peso.text.trim()),
          estaturaCm: double.tryParse(_estatura.text.trim()),
          edad: int.tryParse(_edad.text.trim()),
          actividad: _actividad,
        );
    Navigator.of(context).pop();
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
              const SizedBox(height: 22),
              _dropdown('Objetivo', _objetivo, _objetivos, (v) => setState(() => _objetivo = v ?? _objetivo)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _numField(_peso, 'Peso (kg)', 30, 300)),
                  const SizedBox(width: 12),
                  Expanded(child: _numField(_estatura, 'Estatura (cm)', 100, 230)),
                ],
              ),
              const SizedBox(height: 14),
              _numField(_edad, 'Edad', 12, 100),
              const SizedBox(height: 14),
              _dropdown('Nivel de actividad', _actividad, _actividades, (v) => setState(() => _actividad = v ?? _actividad)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                  label: Text('Generar plan con IA',
                      style: AppTypography.buttonLabel.copyWith(color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, int min, int max) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      decoration: _decoration(label),
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        if (n == null || n < min || n > max) return 'Entre $min y $max';
        return null;
      },
    );
  }

  Widget _dropdown(String label, String value, Map<String, String> options, ValueChanged<String?> onChanged) {
    return InputDecorator(
      decoration: _decoration(label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      floatingLabelStyle: const TextStyle(color: AppColors.neonCyan),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
