/// @file lib/features/home/presentation/screens/home_dashboard_screen.dart
/// @description Dashboard principal con tarjetas de macros, QR dinámico y módulos IA.
/// El contenido hace scroll BAJO la barra de cristal flotante gracias al padding inferior.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/presentation/widgets/glass_surface.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../qr_access/presentation/providers/qr_access_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../widgets/ai_modules_grid.dart';
import '../widgets/dynamic_access_qr_card.dart';
import '../widgets/macro_progress_card.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final subAsync = ref.watch(subscriptionProvider);

    // Altura de la barra de cristal flotante (~72) + fondo de pantalla (~16) + padding
    const double kGlassBarHeight = 72 + 16 + 16;

    return Scaffold(
      backgroundColor: AppColors.background,
      // SIN AppBar — el header va dentro del scroll
      body: RefreshIndicator(
        color: AppColors.neonPink,
        backgroundColor: AppColors.surface,
        displacement: 80,
        onRefresh: () async {
          await ref.read(subscriptionProvider.notifier).fetchSubscription();
          await ref.read(qrAccessProvider.notifier).startDynamicRefresh();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ── STICKY GLASS HEADER ────────────────────────────────────────
            SliverPersistentHeader(
              pinned: true,
              delegate: _GlassAppBarDelegate(
                user: user?.nombre ?? 'Socio GymPro',
                subAsync: subAsync,
                onLogout: () => ref.read(authProvider.notifier).logout(),
              ),
            ),

            // ── CUERPO CON PADDING PARA LA BARRA FLOTANTE ─────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, kGlassBarHeight),
              sliver: SliverList.list(
                children: [
                  // Saludo personalizado
                  _buildGreetingSection(user?.nombre ?? 'Socio GymPro'),
                  const SizedBox(height: 24),

                  // ── TARJETAS DE MACROS DIARIOS ─────────────────────────
                  _buildSectionTitle('Nutrición del Día'),
                  const SizedBox(height: 14),
                  const MacroProgressCard(),
                  const SizedBox(height: 28),

                  // ── TARJETA DE QR DINÁMICO ─────────────────────────────
                  _buildSectionTitle('Acceso Biométrico'),
                  const SizedBox(height: 14),
                  const DynamicAccessQrCard(),
                  const SizedBox(height: 32),

                  // ── GRID DE MÓDULOS IA ─────────────────────────────────
                  _buildSectionTitle('Módulos IA'),
                  const SizedBox(height: 14),
                  const AiModulesGrid(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingSection(String name) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? '¡Buenos días'
        : hour < 18
            ? '¡Buenas tardes'
            : '¡Buenas noches';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting, ${name.split(' ').first}! 💪',
          style: AppTypography.displayMedium.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu entrenamiento inteligente te espera.',
          style: AppTypography.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 1.8,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS APP BAR — Sticky Header con Glassmorphism
// ─────────────────────────────────────────────────────────────────────────────
class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  const _GlassAppBarDelegate({
    required this.user,
    required this.subAsync,
    required this.onLogout,
  });

  final String user;
  final AsyncValue subAsync;
  final VoidCallback onLogout;

  @override
  double get minExtent => kToolbarHeight + 16;
  @override
  double get maxExtent => kToolbarHeight + 24;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final opacity =
        (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    // Cristal premium: blur progresivo al hacer scroll + highlight specular sutil
    // en el filo superior, que da la sensación de un panel de vidrio real.
    return GlassSurface(
      borderRadius: 0,
      blurSigma: 24 * opacity,
      specularOpacity: 0.12,
      tint: AppColors.background.withValues(alpha: 0.85 + 0.15 * opacity),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 20,
        right: 12,
      ),
      child: Row(
            children: [
              // Logo
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'GYMPRO AI',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    subAsync.when(
                      loading: () => Text(
                        'Verificando membresía...',
                        style: AppTypography.caption,
                      ),
                      error: (_, __) => Text(
                        'Sin conexión',
                        style: AppTypography.caption,
                      ),
                      data: (sub) {
                        final s = sub as dynamic;
                        return Text(
                          s.statusDisplayLabel as String? ?? 'Activo',
                          style: AppTypography.caption.copyWith(
                            color: (s.isAccessValid as bool? ?? false)
                                ? AppColors.success
                                : AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Notificaciones
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: AppColors.textSecondary, size: 22),
                onPressed: () {},
              ),
              // Logout
              IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: AppColors.textMuted, size: 20),
                tooltip: 'Cerrar Sesión',
                onPressed: onLogout,
              ),
            ],
      ),
    );
  }

  @override
  bool shouldRebuild(_GlassAppBarDelegate oldDelegate) =>
      oldDelegate.user != user || oldDelegate.subAsync != subAsync;
}
