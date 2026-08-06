/// @file lib/features/home/presentation/widgets/ai_modules_grid.dart
/// @description Grid de módulos IA (Dieta y Rutinas) que llama al pago real en Stripe si está vencido.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../../payment/presentation/widgets/plan_selector_sheet.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../workout/presentation/screens/workout_main_screen.dart';
import '../../../nutrition/presentation/screens/nutrition_main_screen.dart';

class AiModulesGrid extends ConsumerWidget {
  const AiModulesGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAccessValid = ref.watch(isAccessValidProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Coaching inteligente',
                style: AppTypography.titleLarge.copyWith(fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isAccessValid
                    ? AppColors.neonEmerald.withValues(alpha: 0.10)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isAccessValid
                      ? AppColors.neonEmerald.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAccessValid ? Icons.verified_rounded : Icons.lock_rounded,
                    color: isAccessValid ? AppColors.neonEmerald : AppColors.textMuted,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isAccessValid ? 'Activo' : 'Bloqueado',
                    style: AppTypography.caption.copyWith(
                      color: isAccessValid ? AppColors.neonEmerald : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (!isAccessValid)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: Colors.grey, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Las opciones de IA (Dieta y Rutinas) se encuentran desactivadas hasta que se procese correctamente el pago de tu membresía en Stripe.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Row(
          children: [
            Expanded(
              child: _AiModuleCard(
                title: 'Rutinas con IA',
                subtitle: 'Generador hipertrofia y fuerza personalizado',
                icon: Icons.fitness_center_rounded,
                gradientColors: const [AppColors.neonViolet, AppColors.neonCyan],
                isLocked: !isAccessValid,
                onTap: () => _onModuleTapped(context, ref, isAccessValid, 'Rutinas con IA'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _AiModuleCard(
                title: 'Dieta AI Coach',
                subtitle: 'Plan nutricional macro-ajustado en tiempo real',
                icon: Icons.restaurant_menu_rounded,
                gradientColors: const [AppColors.neonPurple, AppColors.neonPink],
                isLocked: !isAccessValid,
                onTap: () => _onModuleTapped(context, ref, isAccessValid, 'Dieta AI Coach'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onModuleTapped(BuildContext context, WidgetRef ref, bool isValid, String moduleName) {
    if (!isValid) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (_) => _LockedModuleBottomSheet(moduleName: moduleName),
      );
    } else {
      // Abrimos la pantalla DIRECTAMENTE con Navigator.push. Antes se usaba
      // shellNavProvider para cambiar de pestaña, pero el login navega directo a
      // HomeDashboardScreen (fuera del AppShell), así que ese provider no tenía
      // efecto → los módulos "no abrían". Con push funciona en ambos casos.
      final Widget screen = moduleName == 'Rutinas con IA'
          ? const WorkoutMainScreen()
          : const NutritionMainScreen();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }
  }
}

class _AiModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isLocked;
  final VoidCallback onTap;

  const _AiModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 180,
      decoration: BoxDecoration(
        color: isLocked ? const Color(0xFF161324) : AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isLocked
              ? Colors.grey.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: isLocked
            ? []
            : [
                BoxShadow(
                  color: gradientColors.first.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: isLocked ? null : LinearGradient(colors: gradientColors),
                        color: isLocked ? const Color(0xFF28243A) : null,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        icon,
                        color: isLocked ? Colors.grey : Colors.white,
                        size: 26,
                      ),
                    ),
                    if (isLocked)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF28243A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.lock_rounded, color: Colors.grey, size: 20),
                      )
                    else
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleLarge.copyWith(
                        fontSize: 17,
                        color: isLocked ? Colors.grey : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLocked ? 'Bloqueado hasta regularizar pago' : subtitle,
                      style: AppTypography.caption.copyWith(
                        color: isLocked ? const Color(0xFF68608C) : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedModuleBottomSheet extends ConsumerWidget {
  final String moduleName;
  const _LockedModuleBottomSheet({required this.moduleName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentState = ref.watch(paymentProvider);
    final isBusy = paymentState.status == PaymentCheckoutStatus.loading;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28, 16, 28, 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFF28243A),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.grey, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            'Módulo de IA Bloqueado',
            style: AppTypography.displayMedium.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 12),
          Text(
            'No puedes acceder a "$moduleName" en este momento. Las funciones de Inteligencia Artificial se encuentran temporalmente inactivas debido a que tu membresía está vencida o con pago pendiente.\n\nAl procesar exitosamente tu pago, tus rutinas y dietas se desbloquearán de inmediato.',
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(isBusy ? 'Conectando con Stripe...' : 'Regularizar Membresía en Stripe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPink,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: isBusy
                  ? null
                  : () => PlanSelectorSheet.show(context, ref),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          ),
          ],
        ),
      ),
    );
  }
}
