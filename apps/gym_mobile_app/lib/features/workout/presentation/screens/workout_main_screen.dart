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
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../providers/workout_provider.dart';
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
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF181528),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.25), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.grey, size: 56),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'MÓDULO DE RUTINAS IA BLOQUEADO',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Las funciones de Inteligencia Artificial para diseño de rutinas anatómicas están desactivadas temporalmente debido a un adeudo o falta de vigencia en tu membresía.\n\nAl regularizar tu pago en Stripe o mostrador, el generador de rutinas y mapa de músculos se activará instantáneamente.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: const Color(0xFF9E96C0),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
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
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 10,
                        shadowColor: AppColors.neonPink.withValues(alpha: 0.4),
                      ),
                      onPressed: paymentState.status == PaymentCheckoutStatus.loading
                          ? null
                          : () => ref.read(paymentProvider.notifier).launchStripeCheckout(),
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
              SizedBox(
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
                'GYMBOT AI DISEÑANDO RUTINA...',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.neonCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mapeando grupos musculares primarios y secundarios',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
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
                'Calculamos tus series, descansos y foco anatómico en base a tus objetivos.',
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
                onPressed: () => ref.read(workoutProvider.notifier).generateRoutinePlan(
                  objetivo: 'hipertrofia',
                  nivel: 'intermedio',
                  lesiones: const ['ninguna'],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
