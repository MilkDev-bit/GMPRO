/// @file lib/core/navigation/app_shell.dart
/// @description Shell principal de la app con navegación flotante de cristal (Glassmorphism).
/// Usa un Stack para que el contenido pase por DEBAJO de la barra como Instagram / Fitia.
/// Adaptativo: Sidebar vertical en tablet/landscape, FloatingBottomBar en mobile/portrait.

library app_shell;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../../features/home/presentation/screens/home_dashboard_screen.dart';
import '../../features/nutrition/presentation/screens/nutrition_main_screen.dart';
import '../../features/qr_access/presentation/screens/qr_access_screen.dart';
import '../../features/subscription/presentation/screens/settings_and_billing_screen.dart';
import '../../features/subscription/presentation/providers/subscription_provider.dart';
import '../../features/workout/presentation/screens/workout_main_screen.dart';
import 'nav_destination.dart';
import 'shell_nav_provider.dart';

export 'nav_destination.dart';
export 'shell_nav_provider.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _barEntryController;
  late final Animation<Offset> _barSlide;
  late final Animation<double> _barFade;

  // ── Páginas indexadas por NavDestination ───────────────────────────────────
  static const List<Widget> _pages = [
    HomeDashboardScreen(),
    QrAccessScreen(),
    NutritionMainScreen(),
    WorkoutMainScreen(),
    SettingsAndBillingScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // El pago con Stripe se hace en el navegador externo (success_url apunta a
    // gmpro.lat, no regresa por deep link), así que la app no se entera del pago
    // por sí sola. Al volver a primer plano refrescamos la suscripción para que
    // la membresía recién pagada se refleje sin recargar la app.
    WidgetsBinding.instance.addObserver(this);
    _barEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _barSlide = Tween<Offset>(
      begin: const Offset(0, 2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _barEntryController,
      curve: Curves.easeOutBack,
    ));
    _barFade = CurvedAnimation(
      parent: _barEntryController,
      curve: Curves.easeOut,
    );
    // Entrada con delay para esperar que Scaffold se pinte primero
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _barEntryController.forward();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barEntryController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresco inmediato + un reintento tras unos segundos para dar tiempo a
      // que el webhook de Stripe procese el pago y active la suscripción.
      final notifier = ref.read(subscriptionProvider.notifier);
      notifier.fetchSubscription();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) notifier.fetchSubscription();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(shellNavProvider);
    final size = MediaQuery.sizeOf(context);
    final isLandscapeOrTablet =
        size.width > 600 || MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Drawer personalizado para mobile (Glassmorphism)
      drawer: isLandscapeOrTablet ? null : _GlassDrawer(selectedIndex: selectedIndex),
      body: Stack(
        children: [
          // ── 1. CONTENIDO PRINCIPAL (pasa DEBAJO del cristal) ───────────────
          IndexedStack(
            index: selectedIndex,
            children: _pages,
          ),

          // ── 2. SIDEBAR FIJO (Tablet / Landscape) ──────────────────────────
          if (isLandscapeOrTablet) _GlassSidebar(selectedIndex: selectedIndex),

          // ── 3. BARRA FLOTANTE DE CRISTAL (Mobile / Portrait) ──────────────
          if (!isLandscapeOrTablet)
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: SlideTransition(
                position: _barSlide,
                child: FadeTransition(
                  opacity: _barFade,
                  child: CustomGlassBottomBar(selectedIndex: selectedIndex),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA FLOTANTE DE CRISTAL (CustomGlassBottomBar)
// ─────────────────────────────────────────────────────────────────────────────
class CustomGlassBottomBar extends ConsumerWidget {
  const CustomGlassBottomBar({super.key, required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            // Fondo OSCURO sólido (no adaptativo al OS): el contenido del shell
            // siempre es oscuro, así que la barra debe serlo también. Antes usaba
            // glassColorOf(context) → en modo claro del sistema se pintaba BLANCA
            // translúcida sobre el fondo oscuro y se veía como una mancha gris.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF232030), Color(0xFF171522)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 26,
                spreadRadius: -2,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: AppColors.neonPurple.withValues(alpha: 0.14),
                blurRadius: 22,
                spreadRadius: -6,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: NavDestination.all.asMap().entries.map((entry) {
              final i = entry.key;
              final dest = entry.value;
              final isSelected = selectedIndex == i;
              return _GlassNavItem(
                destination: dest,
                isSelected: isSelected,
                onTap: () => ref.read(shellNavProvider.notifier).state = i,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ÍTEM DE NAV CON ANIMACIÓN SPRING
// ─────────────────────────────────────────────────────────────────────────────
class _GlassNavItem extends StatefulWidget {
  const _GlassNavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_GlassNavItem> createState() => _GlassNavItemState();
}

class _GlassNavItemState extends State<_GlassNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    if (widget.isSelected) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_GlassNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _ctrl.forward(from: 0.0);
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.destination.accentColor;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Indicador de resplandor activo
              Container(
                width: 40,
                height: 40,
                decoration: widget.isSelected
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.18 * _glow.value),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.45 * _glow.value),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      )
                    : null,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Icon(
                    widget.isSelected
                        ? widget.destination.iconSelected
                        : widget.destination.icon,
                    size: 24,
                    // Inactivo: gris claro fijo (visible sobre la barra oscura),
                    // no textMutedOf(context) que en modo claro del OS quedaba casi
                    // invisible sobre la barra.
                    color: widget.isSelected
                        ? accentColor
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected
                      ? accentColor
                      : Colors.white.withValues(alpha: 0.6),
                ),
                child: Text(widget.destination.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR VERTICAL ADAPTATIVO (Tablet / Landscape) — Estilo Instagram Web
// ─────────────────────────────────────────────────────────────────────────────
class _GlassSidebar extends ConsumerWidget {
  const _GlassSidebar({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWideTablet = MediaQuery.sizeOf(context).width > 900;

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            width: isWideTablet ? 220 : 72,
            decoration: BoxDecoration(
              color: AppColors.glassColorOf(context, alpha: 0.48),
              border: Border(
                right: BorderSide(color: AppColors.glassBorderOf(context), width: 1),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Logo
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isWideTablet ? 20 : 16, vertical: 8),
                    child: isWideTablet
                        ? Row(children: [
                            _buildLogoIcon(),
                            const SizedBox(width: 12),
                            Text(
                              'GYMPRO AI',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                                letterSpacing: 1,
                              ),
                            ),
                          ])
                        : Center(child: _buildLogoIcon()),
                  ),
                  const SizedBox(height: 24),
                  // Ítems de navegación
                  ...NavDestination.all.asMap().entries.map((entry) {
                    final i = entry.key;
                    final dest = entry.value;
                    final isSelected = selectedIndex == i;
                    return _SidebarNavItem(
                      destination: dest,
                      isSelected: isSelected,
                      showLabel: isWideTablet,
                      onTap: () =>
                          ref.read(shellNavProvider.notifier).state = i,
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoIcon() {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.destination,
    required this.isSelected,
    required this.showLabel,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = destination.accentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.symmetric(
          horizontal: showLabel ? 12 : 10,
          vertical: 4,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 16 : 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? destination.iconSelected : destination.icon,
              size: 22,
              color: isSelected ? accentColor : AppColors.textMutedOf(context),
            ),
            if (showLabel) ...[
              const SizedBox(width: 14),
              Text(
                destination.label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAWER PERSONALIZADO CON GLASSMORPHISM (Mobile)
// ─────────────────────────────────────────────────────────────────────────────
class _GlassDrawer extends ConsumerWidget {
  const _GlassDrawer({required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: AppColors.surfaceOf(context).withValues(alpha: 0.92),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'GYMPRO AI',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimaryOf(context),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Divider(color: AppColors.glassBorderOf(context), height: 1),
                  const SizedBox(height: 16),
                  ...NavDestination.all.asMap().entries.map((entry) {
                    final i = entry.key;
                    final dest = entry.value;
                    final isSelected = selectedIndex == i;
                    return _SidebarNavItem(
                      destination: dest,
                      isSelected: isSelected,
                      showLabel: true,
                      onTap: () {
                        ref.read(shellNavProvider.notifier).state = i;
                        Navigator.of(context).pop();
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA PLACEHOLDER PARA SECCIONES AÚN NO IMPLEMENTADAS
// ─────────────────────────────────────────────────────────────────────────────
// ignore: unused_element
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: AppColors.neonPurple.withValues(alpha: 0.5)),
            const SizedBox(height: 20),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Próximamente en GymPro AI',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textMutedOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
