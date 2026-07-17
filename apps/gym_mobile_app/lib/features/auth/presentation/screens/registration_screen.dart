/// @file lib/features/auth/presentation/screens/registration_screen.dart
/// @description Flujo de alta multi-paso passwordless de GymPro con estética Neon Sport
/// Dark + Glassmorphism: datos personales → correo → verificación OTP → Passkey.
/// Estado orquestado con Riverpod (registrationProvider) sin acoplar la UI a la red.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../features/home/presentation/screens/home_dashboard_screen.dart';
import '../providers/registration_provider.dart';
import '../widgets/auth_error_snackbar.dart';
import '../widgets/neon_glow_background.dart';
import '../widgets/neon_text_field.dart';
import '../widgets/otp_input.dart';
import '../widgets/signup_progress_bar.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  static const int _inputSteps = 3; // personalInfo, email, otp

  final _personalFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _pageController = PageController();

  final _nameController = TextEditingController();
  final _birthController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  DateTime? _birthDate;
  String _otpCode = '';

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _birthController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  int _indexFor(RegistrationStep step) => switch (step) {
        RegistrationStep.personalInfo => 0,
        RegistrationStep.email => 1,
        RegistrationStep.otp => 2,
        RegistrationStep.done => 3,
      };

  void _handleBack() {
    final step = ref.read(registrationProvider).step;
    if (step == RegistrationStep.personalInfo) {
      Navigator.of(context).maybePop();
    } else {
      FocusScope.of(context).unfocus();
      ref.read(registrationProvider.notifier).previousStep();
    }
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.neonPurple,
            surface: AppColors.darkSurface,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  void _submitPersonalInfo() {
    if (!(_personalFormKey.currentState?.validate() ?? false)) return;
    if (_birthDate == null) return;
    FocusScope.of(context).unfocus();
    ref.read(registrationProvider.notifier).submitPersonalInfo(
          fullName: _nameController.text.trim(),
          birthDate: _birthDate!,
          phone: _phoneController.text.trim(),
        );
  }

  void _submitEmail() {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    ref.read(registrationProvider.notifier).submitEmail(
          _emailController.text.trim(),
        );
  }

  void _verifyOtp() {
    if (_otpCode.length != 6) return;
    FocusScope.of(context).unfocus();
    ref.read(registrationProvider.notifier).verifyOtpAndRegister(_otpCode);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RegistrationState>(registrationProvider, (prev, next) {
      // Sincroniza el PageView con el paso lógico del provider.
      final targetIndex = _indexFor(next.step);
      if (_pageController.hasClients &&
          _pageController.page?.round() != targetIndex) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
      if (next.status == RegistrationStatus.error && next.errorMessage != null) {
        AuthErrorSnackbar.show(context, next.errorMessage!);
      }
    });

    final state = ref.watch(registrationProvider);
    final isDone = state.step == RegistrationStep.done;

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        textTheme: AppTypography.darkTextTheme,
      ),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: NeonGlowBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    if (!isDone) ...[
                      const SizedBox(height: 8),
                      SignupProgressBar(
                        currentStep: _indexFor(state.step),
                        totalSteps: _inputSteps,
                        onBack: _handleBack,
                      ),
                    ],
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _StepScaffold(child: _buildPersonalStep(state)),
                          _StepScaffold(child: _buildEmailStep(state)),
                          _StepScaffold(child: _buildOtpStep(state)),
                          _buildDoneStep(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Paso 1: Datos personales ───────────────────────────────────────────────
  Widget _buildPersonalStep(RegistrationState state) {
    return Form(
      key: _personalFormKey,
      child: _GlassCard(
        title: 'Crea tu cuenta',
        subtitle: 'Cuéntanos quién eres para personalizar tu entrenamiento.',
        children: [
          NeonTextField(
            controller: _nameController,
            label: 'Nombre completo',
            hint: 'Ej. Milton Pina',
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.name,
            accent: AppColors.neonPurple,
            validator: (v) =>
                (v == null || v.trim().length < 3) ? 'Ingresa tu nombre.' : null,
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _pickBirthDate,
            child: AbsorbPointer(
              child: NeonTextField(
                controller: _birthController,
                label: 'Fecha de nacimiento',
                hint: 'DD/MM/AAAA',
                icon: Icons.cake_outlined,
                accent: AppColors.neonPurple,
                validator: (_) =>
                    _birthDate == null ? 'Selecciona tu fecha.' : null,
              ),
            ),
          ),
          const SizedBox(height: 18),
          NeonTextField(
            controller: _phoneController,
            label: 'Teléfono',
            hint: '+52 55 0000 0000',
            icon: Icons.phone_iphone_rounded,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            accent: AppColors.neonPurple,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
            ],
            validator: (v) => (v == null || v.trim().length < 8)
                ? 'Ingresa un teléfono válido.'
                : null,
          ),
          const SizedBox(height: 28),
          _PrimaryButton(
            label: 'Continuar',
            isLoading: false,
            onPressed: _submitPersonalInfo,
          ),
        ],
      ),
    );
  }

  // ── Paso 2: Correo electrónico ─────────────────────────────────────────────
  Widget _buildEmailStep(RegistrationState state) {
    return Form(
      key: _emailFormKey,
      child: _GlassCard(
        title: '¿Cuál es tu correo?',
        subtitle: 'Te enviaremos un código para confirmar que eres tú.',
        children: [
          NeonTextField(
            controller: _emailController,
            label: 'Correo electrónico',
            hint: 'tu@email.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            accent: AppColors.neonCyan,
            enabled: !state.isSubmitting,
            onSubmitted: (_) => _submitEmail(),
            validator: (v) {
              final email = (v ?? '').trim();
              if (email.isEmpty) return 'Ingresa tu correo.';
              final regex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
              if (!regex.hasMatch(email)) return 'Formato de correo inválido.';
              return null;
            },
          ),
          const SizedBox(height: 28),
          _PrimaryButton(
            label: 'Enviar código',
            isLoading: state.isSubmitting,
            onPressed: _submitEmail,
          ),
        ],
      ),
    );
  }

  // ── Paso 3: Verificación OTP ───────────────────────────────────────────────
  Widget _buildOtpStep(RegistrationState state) {
    return _GlassCard(
      title: 'Verifica tu identidad',
      subtitle: 'Escribe el código de 6 dígitos que enviamos a '
          '${state.email.isEmpty ? 'tu correo' : state.email}.',
      children: [
        OtpInput(
          length: 6,
          hasError: state.otpError,
          enabled: !state.isSubmitting,
          onChanged: (code) => _otpCode = code,
          onCompleted: (code) {
            _otpCode = code;
            _verifyOtp();
          },
        ),
        if (state.otpError) ...[
          const SizedBox(height: 12),
          Text(
            'Código incorrecto. Revísalo e inténtalo otra vez.',
            style: AppTypography.caption.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 22),
        Center(
          child: TextButton(
            onPressed: state.isSubmitting
                ? null
                : () => ref.read(registrationProvider.notifier).resendOtp(),
            child: Text(
              '¿No recibiste el código? Reenviar',
              style: AppTypography.caption.copyWith(
                color: AppColors.neonCyan.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: 'Verificar y crear Passkey',
          isLoading: state.isSubmitting,
          onPressed: _verifyOtp,
        ),
      ],
    );
  }

  // ── Paso final: Éxito ──────────────────────────────────────────────────────
  Widget _buildDoneStep() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.neonEmerald, AppColors.neonCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonEmerald.withValues(alpha: 0.5),
                    blurRadius: 38,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 56),
            ),
            const SizedBox(height: 28),
            Text(
              '¡Cuenta lista!',
              style: AppTypography.displayMedium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              'Tu Passkey biométrica quedó vinculada a este dispositivo. '
              'Ya puedes entrenar con GymPro.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 36),
            _PrimaryButton(
              label: 'Entrar a GymPro',
              isLoading: false,
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
                (route) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contenedor scrollable centrado para cada paso ────────────────────────────
class _StepScaffold extends StatelessWidget {
  final Widget child;
  const _StepScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: child,
    );
  }
}

// ── Tarjeta Glassmorphism reutilizable de paso ───────────────────────────────
class _GlassCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _GlassCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary aísla el BackdropFilter para mantener 60/120 FPS.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 30),
            decoration: BoxDecoration(
              color: const Color(0xFF18152D).withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.displayMedium.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Botón primario con gradiente neón ────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: AppTypography.buttonLabel.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
