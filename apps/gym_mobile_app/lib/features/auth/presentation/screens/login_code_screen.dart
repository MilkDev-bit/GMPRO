/// @file lib/features/auth/presentation/screens/login_code_screen.dart
/// @description Acceso por CÓDIGO de email (recuperación sin passkey). Flujo:
///   email → /login/otp/request → OTP 6 dígitos → /login/otp/verify → sesión.
/// Al abrir sesión, el redirect de GoRouter lleva a home automáticamente.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/recovery_provider.dart';
import '../widgets/neon_text_field.dart';
import '../widgets/otp_input.dart';

class LoginCodeScreen extends ConsumerStatefulWidget {
  const LoginCodeScreen({super.key});

  @override
  ConsumerState<LoginCodeScreen> createState() => _LoginCodeScreenState();
}

class _LoginCodeScreenState extends ConsumerState<LoginCodeScreen> {
  final _emailController = TextEditingController();
  String _code = '';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _snack('Ingresa un correo válido.');
      return;
    }
    final ok = await ref.read(recoveryProvider.notifier).requestLoginCode(email);
    if (ok && mounted) _snack('Si el correo está registrado, te enviamos un código.');
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    await ref.read(recoveryProvider.notifier).verifyLoginCode(_code);
    // Si entra, el redirect de GoRouter navega a home solo. Si falla, el estado
    // pasa a error y se muestra abajo.
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recoveryProvider);
    final busy = state.isLoading;
    final codeSent = state.status == RecoveryStatus.codeSent ||
        (state.status == RecoveryStatus.error && state.email.isNotEmpty && _code.isNotEmpty);

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Entrar con código'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  codeSent ? 'Revisa tu correo' : '¿Perdiste tu teléfono?',
                  style: AppTypography.titleLarge.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  codeSent
                      ? 'Escribe el código de 6 dígitos que enviamos a ${_emailController.text.trim()}.'
                      : 'Te enviaremos un código de acceso a tu correo para entrar en este dispositivo y volver a registrar tu Passkey.',
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 26),

                if (!codeSent) ...[
                  NeonTextField(
                    controller: _emailController,
                    label: 'Correo electrónico',
                    hint: 'tu@email.com',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    accent: AppColors.neonCyan,
                    enabled: !busy,
                    onSubmitted: (_) => _sendCode(),
                  ),
                  const SizedBox(height: 22),
                  _PrimaryButton(
                    label: 'Enviar código',
                    icon: Icons.mark_email_read_rounded,
                    busy: busy,
                    onTap: _sendCode,
                  ),
                ] else ...[
                  OtpInput(
                    length: 6,
                    enabled: !busy,
                    hasError: state.status == RecoveryStatus.error,
                    onChanged: (v) => _code = v,
                    onCompleted: (v) {
                      _code = v;
                      _verify();
                    },
                  ),
                  const SizedBox(height: 22),
                  _PrimaryButton(
                    label: 'Verificar y entrar',
                    icon: Icons.login_rounded,
                    busy: busy,
                    onTap: _verify,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: busy ? null : _sendCode,
                      child: Text('¿No recibiste el código? Reenviar',
                          style: AppTypography.caption.copyWith(color: AppColors.neonCyan)),
                    ),
                  ),
                ],

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

/// Botón primario con degradado de marca (local para no acoplar al login_screen).
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.neonPurple, AppColors.neonPink]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: busy ? null : onTap,
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
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(label,
                          style: AppTypography.buttonLabel
                              .copyWith(color: Colors.white, fontSize: 16)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
