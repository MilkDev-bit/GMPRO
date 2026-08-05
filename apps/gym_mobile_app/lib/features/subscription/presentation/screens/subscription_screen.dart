/// @file lib/features/subscription/presentation/screens/subscription_screen.dart
/// @description Pantalla de cuenta y membresía con información de suscripción y portal de Stripe.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../../../payment/presentation/providers/payment_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final subAsync = ref.watch(subscriptionProvider);
    final paymentState = ref.watch(paymentProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header con avatar del usuario
          SliverToBoxAdapter(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.neonPurple, AppColors.neonPink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonPink.withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (user?.nombre ?? 'S').substring(0, 1).toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.nombre ?? 'Socio GymPro',
                      style: AppTypography.displayMedium.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),

          // Tarjeta de membresía
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
            sliver: SliverList.list(
              children: [
                subAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.neonPink,
                    ),
                  ),
                  error: (e, _) => Text('Error: $e',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.error)),
                  data: (sub) {
                    final s = sub as dynamic;
                    final isActive = s.isAccessValid as bool? ?? false;
                    return _MembershipCard(
                      isActive: isActive,
                      statusLabel: s.statusDisplayLabel as String? ?? 'Desconocido',
                      validUntil: s.validoHasta,
                      planName: s.planNombre as String? ?? 'Plan GymPro',
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Botón de gestión de suscripción (Portal Stripe real)
                _GradientButton(
                  label: 'Gestionar Membresía',
                  icon: Icons.credit_card_rounded,
                  gradient: const LinearGradient(
                    colors: [AppColors.neonPurple, AppColors.neonPink],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  isLoading: paymentState.isLoading,
                  onTap: () => ref.read(paymentProvider.notifier).openCustomerPortal(),
                ),
                const SizedBox(height: 12),

                // Botón de cerrar sesión
                _OutlineButton(
                  label: 'Cerrar Sesión',
                  icon: Icons.logout_rounded,
                  onTap: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE MEMBRESÍA
// ─────────────────────────────────────────────────────────────────────────────
class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.isActive,
    required this.statusLabel,
    required this.validUntil,
    required this.planName,
  });

  final bool isActive;
  final String statusLabel;
  final dynamic validUntil;
  final String planName;

  @override
  Widget build(BuildContext context) {
    final accentColor = isActive ? AppColors.success : AppColors.error;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isActive
                  ? [const Color(0xFF0D2918), const Color(0xFF0A1A14)]
                  : [const Color(0xFF2A0A14), const Color(0xFF1A0A10)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.7),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.credit_card_rounded,
                      color: AppColors.textMuted, size: 20),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                planName,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              if (validUntil != null)
                Text(
                  isActive
                      ? 'Válido hasta el ${_formatDate(validUntil)}'
                      : 'Venció el ${_formatDate(validUntil)}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: isActive ? AppColors.textSecondary : AppColors.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    try {
      final d = date is DateTime ? date : DateTime.parse(date.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return 'N/A';
    }
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.isLoading,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Gradient gradient;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58,
        decoration: BoxDecoration(
          gradient: isLoading
              ? const LinearGradient(colors: [Color(0xFF2A2040), Color(0xFF2A2040)])
              : gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: AppColors.neonPink.withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x30FFFFFF), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
