/// @file lib/features/home/presentation/widgets/ai_modules_grid.dart
/// @description Grid de módulos IA (Dieta y Rutinas) que llama al pago real en Stripe si está vencido.
/// UI alineada al design system calmado (openGym): superficies neutras, acento único por
/// módulo (esmeralda/cian), estado con PillTag. La lógica de acceso/pago no se toca.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/presentation/widgets/pill_tag.dart';
import '../../../../core/presentation/widgets/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
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
                style: AppTypography.titleLargeOf(context).copyWith(fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            PillTag(
              label: isAccessValid ? 'Activo' : 'Bloqueado',
              icon: isAccessValid ? Icons.bolt_rounded : Icons.lock_outline_rounded,
              tone: isAccessValid ? PillTone.active : PillTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        if (!isAccessValid)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
            ),
            child: Text(
              'Las opciones de IA (Dieta y Rutinas) se encuentran desactivadas hasta que se procese correctamente el pago de tu membresía en Stripe.',
              style: AppTypography.bodyMediumOf(context).copyWith(
                color: AppColors.textSecondaryOf(context),
                fontSize: 13,
              ),
            ),
          ),

        Row(
          children: [
            Expanded(
              child: _AiModuleCard(
                title: 'Rutinas con IA',
                subtitle: 'Generador hipertrofia y fuerza personalizado',
                icon: Icons.fitness_center_rounded,
                accent: AppColors.accentEmeraldOf(context),
                isLocked: !isAccessValid,
                onTap: () => _onModuleTapped(context, ref, isAccessValid, 'Rutinas con IA'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _AiModuleCard(
                title: 'Dieta AI',
                subtitle: 'Plan nutricional macro-ajustado en tiempo real',
                icon: Icons.restaurant_rounded,
                accent: AppColors.accentCyanOf(context),
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
  final Color accent;
  final bool isLocked;
  final VoidCallback onTap;

  const _AiModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Cuando está bloqueado, el acento se neutraliza (gris) para no invitar al tap.
    final effectiveAccent =
        isLocked ? AppColors.textMutedOf(context) : accent;

    return Pressable(
      haptic: PressHaptic.selection,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 172,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: isLocked
                ? AppColors.glassBorderOf(context)
                : accent.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícono cuadrado con acento (o candado si está bloqueado).
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: effectiveAccent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                    color: effectiveAccent.withValues(alpha: 0.35), width: 1),
              ),
              child: Icon(
                isLocked ? Icons.lock_rounded : icon,
                size: 22,
                color: effectiveAccent,
              ),
            ),
            const Spacer(),
            Text(
              title,
              style: AppTypography.buttonLabelOf(context).copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isLocked
                    ? AppColors.textSecondaryOf(context)
                    : AppColors.textPrimaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              isLocked ? 'Bloqueado hasta regularizar pago' : subtitle,
              style: AppTypography.bodyMediumOf(context).copyWith(
                color: isLocked
                    ? AppColors.textMutedOf(context)
                    : AppColors.textSecondaryOf(context),
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
