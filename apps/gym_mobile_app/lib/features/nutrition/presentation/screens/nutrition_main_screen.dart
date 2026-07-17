/// @file lib/features/nutrition/presentation/screens/nutrition_main_screen.dart
/// @description Contenedor principal de Nutrición IA (Tab 2). Si la membresía está inactiva
/// (!isAccessValid), muestra la interfaz del plan dietético difuminada tras un cristal
/// esmerilado (BackdropFilter) con una tarjeta flotante de bloqueo con acentos magenta
/// y botón elástico para regularizar con Stripe.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../providers/nutrition_provider.dart';
import 'nutrition_plan_screen.dart';

class NutritionMainScreen extends ConsumerWidget {
  const NutritionMainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAccessValid = ref.watch(isAccessValidProvider);
    final nutritionState = ref.watch(nutritionProvider);
    final paymentState = ref.watch(paymentProvider);

    // ── CASO A: SUSCRIPCIÓN INACTIVA (CRISTAL ESMERILADO SOBRE PLAN FONDO) ───
    if (!isAccessValid) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Fondo difuminado: muestra el plan pero inhabilitado a la interacción
            IgnorePointer(
              child: Opacity(
                opacity: 0.45,
                child: NutritionPlanScreen(
                  plan: nutritionState.plan ?? ref.read(nutritionProvider.notifier).state.plan!,
                ),
              ),
            ),
            // Capa de desenfoque progresivo
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: const Color(0xFF0C0A18).withValues(alpha: 0.65),
                ),
              ),
            ),
            // Tarjeta central flotante de bloqueo con resplandor magenta
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                physics: const BouncingScrollPhysics(),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF26183A).withValues(alpha: 0.94),
                        const Color(0xFF140E24).withValues(alpha: 0.98),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(38),
                    border: Border.all(
                      color: AppColors.neonPink.withValues(alpha: 0.55),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonPink.withValues(alpha: 0.28),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingLockIcon(),
                      const SizedBox(height: 26),
                      Text(
                        'DIETA AI COACH BLOQUEADA',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'El cálculo inteligente de macronutrientes, hidratación y búsqueda de porciones sobre el catálogo Open Food Facts requieren una membresía activa.\n\nRegulariza tu acceso con Stripe para desbloquear en milisegundos todas las herramientas de nutrición de alto rendimiento.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: const Color(0xFFB8AFE0),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 34),
                      _ElasticStripeButton(
                        isLoading: paymentState.status == PaymentCheckoutStatus.loading,
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          ref.read(paymentProvider.notifier).launchStripeCheckout();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── CASO B: CARGANDO PLAN DESDE AI-SERVICE ───────────────────────────────
    if (nutritionState.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: CircularProgressIndicator(
                  strokeWidth: 4.5,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonPurple),
                  backgroundColor: AppColors.neonPurple.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'GYMBOT AI CALCULANDO TUS MACROS...',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonPurple,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sincronizando porciones con el catálogo Open Food Facts',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // ── CASO C: PLAN ACTIVO ──────────────────────────────────────────────────
    if (nutritionState.plan != null) {
      return NutritionPlanScreen(plan: nutritionState.plan!);
    }

    // ── CASO D: ESTADO INICIAL O FALLBACK ────────────────────────────────────
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.restaurant_menu_rounded, color: AppColors.neonCyan, size: 72),
              const SizedBox(height: 24),
              Text('Dieta AI Coach', style: AppTypography.displayMedium),
              const SizedBox(height: 14),
              Text(
                'Ajustamos tus calorías y macronutrientes exactamente a tus requerimientos deportivos usando alimentos reales de Open Food Facts.',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded, size: 22),
                label: Text(
                  'Generar Plan Nutricional IA',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 12,
                  shadowColor: AppColors.neonCyan.withValues(alpha: 0.4),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(nutritionProvider.notifier).generateDietPlan();
                },
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _PulsingLockIcon extends StatefulWidget {
  @override
  State<_PulsingLockIcon> createState() => _PulsingLockIconState();
}

class _PulsingLockIconState extends State<_PulsingLockIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.neonPink.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonPink.withValues(alpha: 0.4),
              blurRadius: 24,
            ),
          ],
        ),
        child: const Icon(Icons.lock_rounded, color: AppColors.neonPink, size: 54),
      ),
    );
  }
}

class _ElasticStripeButton extends StatefulWidget {
  const _ElasticStripeButton({required this.isLoading, required this.onPressed});
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  State<_ElasticStripeButton> createState() => _ElasticStripeButtonState();
}

class _ElasticStripeButtonState extends State<_ElasticStripeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.isLoading ? null : _controller.forward(),
      onTapUp: (_) {
        if (!widget.isLoading) {
          _controller.reverse();
          widget.onPressed();
        }
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.neonPink, Color(0xFFD6006C)],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonPink.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              else
                const Icon(Icons.payment_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                widget.isLoading ? 'Conectando con Stripe...' : 'Regularizar Membresía (Stripe)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
