/// @file lib/features/workout/presentation/widgets/workout_profile_sheet.dart
/// @description Formulario para capturar los datos de entrenamiento del socio
/// (objetivo, nivel, días por semana, lesiones) y generar la rutina en el
/// ai-service, que arma los ejercicios desde el catálogo de wger y las
/// características del usuario. Antes la rutina era un plan mock hardcodeado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/workout_provider.dart';

class WorkoutProfileSheet extends ConsumerStatefulWidget {
  const WorkoutProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const WorkoutProfileSheet(),
    );
  }

  @override
  ConsumerState<WorkoutProfileSheet> createState() => _WorkoutProfileSheetState();
}

class _WorkoutProfileSheetState extends ConsumerState<WorkoutProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lesiones;
  String _objetivo = 'hipertrofia';
  String _nivel = 'intermedio';
  int _dias = 4;

  static const Map<String, String> _objetivos = {
    'hipertrofia': 'Ganar músculo (hipertrofia)',
    'fuerza': 'Fuerza',
    'resistencia': 'Resistencia',
    'perdida_grasa': 'Pérdida de grasa',
  };
  static const Map<String, String> _niveles = {
    'principiante': 'Principiante',
    'intermedio': 'Intermedio',
    'avanzado': 'Avanzado',
  };

  @override
  void initState() {
    super.initState();
    final p = ref.read(workoutProvider).profile;
    _objetivo = _objetivos.containsKey(p.objetivo) ? p.objetivo : 'hipertrofia';
    _nivel = _niveles.containsKey(p.nivel) ? p.nivel : 'intermedio';
    _dias = (p.diasPorSemana >= 1 && p.diasPorSemana <= 7) ? p.diasPorSemana : 4;
    _lesiones = TextEditingController(
      text: (p.lesiones.isEmpty || p.lesiones == 'ninguna') ? '' : p.lesiones,
    );
  }

  @override
  void dispose() {
    _lesiones.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final lesiones = _lesiones.text.trim();
    ref.read(workoutProvider.notifier).generateRoutinePlan(
          objetivo: _objetivo,
          nivel: _nivel,
          diasPorSemana: _dias,
          lesiones: lesiones.isEmpty ? 'ninguna' : lesiones,
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
              Text('Tu rutina a tu medida', style: AppTypography.titleLarge.copyWith(fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                'Con estos datos armamos tu rutina con ejercicios reales del catálogo wger.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              _dropdown('Objetivo', _objetivo, _objetivos, (v) => setState(() => _objetivo = v ?? _objetivo)),
              const SizedBox(height: 14),
              _dropdown('Nivel', _nivel, _niveles, (v) => setState(() => _nivel = v ?? _nivel)),
              const SizedBox(height: 14),
              _diasSelector(),
              const SizedBox(height: 14),
              TextFormField(
                controller: _lesiones,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                decoration: _decoration('Lesiones / limitaciones (opcional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: Text('Generar rutina con IA',
                      style: AppTypography.buttonLabel.copyWith(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonPurple,
                    foregroundColor: Colors.white,
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

  Widget _diasSelector() {
    return InputDecorator(
      decoration: _decoration('Días por semana'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (i) {
          final dias = i + 3; // 3..6
          final selected = _dias == dias;
          return GestureDetector(
            onTap: () => setState(() => _dias = dias),
            child: Container(
              width: 48,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.neonPurple : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.neonPurple : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                '$dias',
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ),
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
      floatingLabelStyle: const TextStyle(color: AppColors.neonPurple),
      filled: true,
      fillColor: AppColors.surfaceElevated,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.neonPurple, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
