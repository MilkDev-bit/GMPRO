/// @file lib/features/workout/presentation/screens/workout_main_screen.dart
/// @description Contenedor principal de Rutinas IA. Cumple con Tarea 4.2 verificando
/// el estado de membresía (isAccessValidProvider): bloquea con candado visual si está
/// inactiva o muestra el mapa anatómico interactivo si está al corriente.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../../payment/presentation/widgets/plan_selector_sheet.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../providers/workout_provider.dart';
import '../widgets/workout_profile_sheet.dart';
import 'workout_plan_screen.dart';

class WorkoutMainScreen extends ConsumerWidget {
  const WorkoutMainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Escuchar el derecho de acceso a IA del usuario (Tarea 4.2)
    final isAccessValid = ref.watch(isAccessValidProvider);
    final workoutState = ref.watch(workoutProvider);
    final paymentState = ref.watch(paymentProvider);

    // ── CASO A: SUSCRIPCIÓN VENCIDA O INACTIVA (CANDADO DE BLOQUEO) ─────────
    if (!isAccessValid) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 44),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Rutinas con IA bloqueadas',
                    style: AppTypography.titleLarge.copyWith(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'El generador de rutinas y el mapa muscular se activan al instante cuando regularizas tu membresía.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: paymentState.status == PaymentCheckoutStatus.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.payment_rounded, size: 20),
                      label: Text(
                        paymentState.status == PaymentCheckoutStatus.loading
                            ? 'Conectando con Stripe...'
                            : 'Regularizar Membresía (Stripe)',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonPink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: paymentState.status == PaymentCheckoutStatus.loading
                          ? null
                          : () => PlanSelectorSheet.show(context, ref),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── CASO B: CARGANDO RUTINA DESDE AI-SERVICE ────────────────────────────
    if (workoutState.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonCyan),
                  backgroundColor: AppColors.surfaceElevated,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Diseñando tu rutina',
                style: AppTypography.titleLarge.copyWith(color: AppColors.neonCyan, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Mapeando grupos musculares primarios y secundarios',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // ── CASO C: RUTINA LISTA O DEMO ACTIVA ──────────────────────────────────
    if (workoutState.plan != null) {
      return WorkoutPlanScreen(plan: workoutState.plan!);
    }

    // ── CASO D: ESTADO INICIAL (BOTÓN PARA REGENERAR) ───────────────────────
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.neonPurple, size: 64),
              const SizedBox(height: 20),
              Text('Generador de Rutinas IA', style: AppTypography.displayMedium),
              const SizedBox(height: 12),
              Text(
                'Armamos tu rutina con ejercicios reales de nuestro catálogo, en base a tu objetivo, nivel y tus datos.',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Generar Rutina Personalizada'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                ),
                onPressed: () => WorkoutProfileSheet.show(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
