/// @file lib/features/auth/presentation/screens/login_screen.dart
/// @description Pantalla de autenticación nativa (Apple/Google) con diseño Neon Sport Dark + Organic Cards.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart'; // self
import '../widgets/auth_error_snackbar.dart';
import '../widgets/neon_glow_background.dart';
import '../widgets/social_login_button.dart';
import '../../../../features/home/presentation/screens/home_dashboard_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutQuart,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Escuchar cambios en el estado de autenticación (Riverpod)
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        AuthErrorSnackbar.show(context, next.errorMessage!);
      } else if (next.status == AuthStatus.authenticated && next.user != null) {
        // Redirigir al área principal de miembros de GymPro
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomeDashboardScreen(),
          ),
        );
      }
    });

    final authState = ref.watch(authProvider);
    final isBusy = authState.status == AuthStatus.loading;

    return Scaffold(
      body: NeonGlowBackground(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo y Resplandor Neón Sport ───────────────────────────
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonPink.withValues(alpha: 0.5),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.fitness_center_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Título Principal (Google Fonts Outfit) ─────────────────
                  Text(
                    'GYMPRO',
                    style: AppTypography.displayLarge.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Alto Rendimiento & Acceso Biométrico',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // ── Tarjeta Orgánica con Selectores Píldora ────────────────
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido de vuelta',
                          style: AppTypography.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ingresa con tu cuenta nativa verificada por tu dispositivo.',
                          style: AppTypography.bodyMedium,
                        ),
                        const SizedBox(height: 32),

                        // ── Botón Apple ID Sign-In (Nativo iOS / FaceID) ─────
                        if (Platform.isIOS || Platform.isMacOS) ...[
                          SocialLoginButton(
                            label: 'Continuar con Apple ID',
                            icon: Icons.apple_rounded,
                            backgroundColor: Colors.white,
                            textColor: Colors.black,
                            isLoading: isBusy,
                            onPressed: () =>
                                ref.read(authProvider.notifier).loginWithApple(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Botón Google Sign-In (Nativo Android & iOS) ──────
                        SocialLoginButton(
                          label: 'Continuar con Google',
                          icon: Icons.g_mobiledata_rounded,
                          backgroundColor: AppColors.surfaceElevated,
                          textColor: Colors.white,
                          borderColor: AppColors.neonPurple.withValues(alpha: 0.6),
                          isLoading: isBusy,
                          onPressed: () =>
                                ref.read(authProvider.notifier).loginWithGoogle(),
                        ),

                        const SizedBox(height: 24),

                        // ── Indicación de Privacidad y Token Seguro ──────────
                        Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: AppColors.neonCyan.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tus tokens se cifran en hardware (AES-256 / Keychain).',
                                style: AppTypography.caption.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),
                  Text(
                    '© 2026 GymPro Technologies Inc.',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

