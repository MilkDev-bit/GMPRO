/// @file lib/features/auth/presentation/screens/login_password_screen.dart
/// @description Acceso por email + contraseña (recuperación / dispositivo nuevo).
///   email + password → /login → sesión. Enlace "¿Olvidaste tu contraseña?" →
///   /password/forgot (envía email con deep link gympro://reset-password?token=).
/// Al abrir sesión, el redirect de GoRouter navega a home automáticamente.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/recovery_provider.dart';
import '../widgets/neon_text_field.dart';

class LoginPasswordScreen extends ConsumerStatefulWidget {
  const LoginPasswordScreen({super.key});

  @override
  ConsumerState<LoginPasswordScreen> createState() => _LoginPasswordScreenState();
}

class _LoginPasswordScreenState extends ConsumerState<LoginPasswordScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    if (!email.contains('@') || pass.isEmpty) {
      _snack('Ingresa tu correo y contraseña.');
      return;
    }
    await ref.read(recoveryProvider.notifier).loginWithPassword(email, pass);
    // Si entra, el redirect de GoRouter navega a home. Si falla, se muestra abajo.
  }

  Future<void> _forgot() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _snack('Escribe tu correo primero para enviarte el enlace.');
      return;
    }
    await ref.read(recoveryProvider.notifier).forgotPassword(email);
    if (mounted) {
      _snack('Si el correo está registrado, te enviamos un enlace para restablecer tu contraseña.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recoveryProvider);
    final busy = state.isLoading;

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Entrar con contraseña'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Inicia sesión',
                    style: AppTypography.titleLarge.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'Usa tu correo y contraseña. Útil si perdiste el acceso a tu Passkey.',
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 26),

                NeonTextField(
                  controller: _emailController,
                  label: 'Correo electrónico',
                  hint: 'tu@email.com',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  accent: AppColors.neonCyan,
                  enabled: !busy,
                ),
                const SizedBox(height: 18),
                NeonTextField(
                  controller: _passwordController,
                  label: 'Contraseña',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  obscureText: true,
                  accent: AppColors.neonPurple,
                  enabled: !busy,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy ? null : _forgot,
                    child: Text('¿Olvidaste tu contraseña?',
                        style: AppTypography.caption.copyWith(color: AppColors.neonCyan)),
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.neonPurple, AppColors.neonPink]),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: busy ? null : _login,
                      child: Center(
                        child: busy
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.login_rounded, color: Colors.white, size: 22),
                                  const SizedBox(width: 10),
                                  Text('Iniciar sesión',
                                      style: AppTypography.buttonLabel
                                          .copyWith(color: Colors.white, fontSize: 16)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),

                if (state.status == RecoveryStatus.error && state.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(state.errorMessage!,
                      style: AppTypography.caption.copyWith(color: AppColors.neonPink)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
