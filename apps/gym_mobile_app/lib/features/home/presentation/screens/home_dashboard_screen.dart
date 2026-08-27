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
      backgroundColor: const Color(0xFF09090B),
      // SIN AppBar — el header va dentro del scroll
      body: Stack(
        children: [
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x151EE083), // Emerald green with very low opacity
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          RefreshIndicator(
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
                topPadding: MediaQuery.of(context).padding.top,
              ),
            ),

            // ── CUERPO CON PADDING PARA LA BARRA FLOTANTE ─────────────────
            SliverPadding(
              // +safe-area inferior: si no, la última tarjeta queda tras la barra
              // flotante en teléfonos con barra de gestos.
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, kGlassBarHeight + MediaQuery.of(context).padding.bottom),
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
      ],
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
          '$greeting, ${name.split(' ').first}',
          style: AppTypography.displayMedium.copyWith(fontSize: 28, height: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu entrenamiento inteligente te espera.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
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
    required this.topPadding,
  });

  final String user;
  final AsyncValue subAsync;
  final double topPadding; // inset de la barra de estado (safe area superior)

  // El header DEBE incluir el inset superior en su altura; si no, el contenido
  // (logo + estado) se salía por abajo (~6px overflow en pantallas con notch).
  @override
  double get minExtent => kToolbarHeight + topPadding + 8;
  @override
  double get maxExtent => kToolbarHeight + topPadding + 16;

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
        top: topPadding,
        left: 20,
        right: 12,
      ),
      child: Row(
            children: [
              // Logo text only
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                        children: const [
                          TextSpan(
                            text: 'GYM',
                            style: TextStyle(color: Colors.white),
                          ),
                          TextSpan(
                            text: 'PRO',
                            style: TextStyle(color: AppColors.neonCyan),
                          ),
                        ],
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
              // El botón de cerrar sesión se retiró del header: el flujo de logout
              // (con su confirmación) vive en la pantalla de Cuenta/Ajustes.
            ],
      ),
    );
  }

  @override
  bool shouldRebuild(_GlassAppBarDelegate oldDelegate) =>
      oldDelegate.user != user ||
      oldDelegate.subAsync != subAsync ||
      oldDelegate.topPadding != topPadding;
}
