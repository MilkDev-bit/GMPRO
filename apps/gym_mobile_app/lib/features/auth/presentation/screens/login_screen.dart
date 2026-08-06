/// @file lib/features/auth/presentation/screens/login_screen.dart
/// @description Pantalla de autenticación GymPro (Passkey / Apple / Google) rediseñada
/// con estética Neon Sport Dark + Glassmorphism flotante, campo de email prominente,
/// jerarquía tipo onboarding premium y animaciones staggered (easeOutCubic).

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_error_snackbar.dart';
import '../widgets/neon_glow_background.dart';
import '../widgets/neon_text_field.dart';
import '../widgets/social_login_button.dart';
import 'registration_screen.dart';
import 'login_code_screen.dart';
import 'login_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  late final AnimationController _entryController;
  bool _showOtherMethods = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Construye una animación escalonada (fade + slide) para el índice dado.
  Widget _staggered(int index, Widget child) {
    final start = (index * 0.09).clamp(0.0, 0.7);
    final animation = CurvedAnimation(
      parent: _entryController,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, innerChild) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - animation.value)),
            child: innerChild,
          ),
        );
      },
      child: child,
    );
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Ingresa tu correo electrónico.';
    final regex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!regex.hasMatch(email)) return 'El correo no tiene un formato válido.';
    return null;
  }

  void _submitPasskey() {
    if (_formKey.currentState?.validate() ?? false) {
      FocusScope.of(context).unfocus();
      ref
          .read(authProvider.notifier)
          .loginWithPasskey(email: _emailController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Solo mostramos errores aquí. La navegación a la app (AppShell) la gobierna
    // main.dart de forma REACTIVA según authState.isAuthenticated — no hacemos
    // push manual: hacerlo dejaba una HomeDashboardScreen "suelta" encima del
    // shell, y al cerrar sesión esa ruta seguía tapando el LoginScreen (la sesión
    // "no se cerraba") y los módulos no reaccionaban sin recargar.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        AuthErrorSnackbar.show(context, next.errorMessage!);
      }
    });

    final authState = ref.watch(authProvider);
    final isBusy = authState.status == AuthStatus.loading;

    // El login siempre se muestra sobre el fondo obsidiana; forzamos contexto
    // oscuro para que los widgets adaptativos (NeonTextField) resuelvan al
    // esquema Neon Sport Dark aunque el SO esté en ThemeMode.light.
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        textTheme: AppTypography.darkTextTheme,
      ),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: NeonGlowBackground(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _staggered(0, _buildBrand()),
                    const SizedBox(height: 36),
                    _staggered(1, _buildAuthCard(isBusy)),
                    const SizedBox(height: 20),
                    _staggered(6, _buildCreateAccountLink(isBusy)),
                    const SizedBox(height: 20),
                    _staggered(6, _buildFooter()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Gradiente de marca ATENUADO: mezcla un 22% con el fondo obsidiana para
  /// bajar la saturación (el neón puro "quemaba" en pantalla) sin perder la
  /// identidad Neon Sport.
  static final LinearGradient _brandGradientSoft = LinearGradient(
    colors: [
      Color.lerp(AppColors.neonPurple, AppColors.darkBackground, 0.22)!,
      Color.lerp(AppColors.neonPink, AppColors.darkBackground, 0.22)!,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Marca ──────────────────────────────────────────────────────────────────
  Widget _buildBrand() {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            style: AppTypography.displayLarge.copyWith(letterSpacing: 3.0),
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
      ],
    );
  }

  // ── Tarjeta Glassmorphism principal ────────────────────────────────────────
  Widget _buildAuthCard(bool isBusy) {
    // RepaintBoundary aísla el BackdropFilter (costoso) del resto del árbol
    // para no repintar los orbes neón en cada frame → 60/120 FPS estables.
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
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bienvenido de vuelta',
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ingresa tu correo para continuar con acceso sin contraseña.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // ── Campo de email (protagonista del formulario) ───────────
                  _staggered(
                    2,
                    NeonTextField(
                      controller: _emailController,
                      label: 'Correo electrónico',
                      hint: 'tu@email.com',
                      icon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      validator: _validateEmail,
                      accent: AppColors.neonCyan,
                      enabled: !isBusy,
                      onSubmitted: (_) => _submitPasskey(),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── CTA primario: Passkey con hint de email ────────────────
                  _staggered(3, _buildPrimaryButton(isBusy)),
                  const SizedBox(height: 14),

                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _showOtherMethods = !_showOtherMethods;
                        });
                      },
                      child: Text(
                        _showOtherMethods ? 'Ocultar opciones' : 'Entrar de otra manera',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.darkTextSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _showOtherMethods
                        ? Column(
                            children: [
                              Center(
                                child: TextButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => ref
                                          .read(authProvider.notifier)
                                          .loginWithPasskey(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.neonCyan,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                  ),
                                  child: Text(
                                    '¿Prefieres tu biometría directamente?',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.neonCyan.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 2,
                                  children: [
                                    TextButton(
                                      onPressed: isBusy
                                          ? null
                                          : () => Navigator.of(context).push(
                                                MaterialPageRoute(
                                                    builder: (_) => const LoginPasswordScreen()),
                                              ),
                                      child: Text(
                                        'Entrar con contraseña',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.darkTextSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isBusy
                                          ? null
                                          : () => Navigator.of(context).push(
                                                MaterialPageRoute(
                                                    builder: (_) => const LoginCodeScreen()),
                                              ),
                                      child: Text(
                                        'Entrar con código',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.neonPink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 6),

                  _staggered(4, _buildDivider()),
                  const SizedBox(height: 20),

                  // ── Proveedores sociales nativos ───────────────────────────
                  _staggered(5, _buildSocialButtons(isBusy)),
                  const SizedBox(height: 22),

                  _buildSecurityNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(bool isBusy) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: _brandGradientSoft,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          // Sombra de color contenida (antes 0.4/24 saturaba todo el bloque).
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: isBusy ? null : _submitPasskey,
          child: Center(
            child: isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fingerprint_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Continuar con Passkey',
                        style: AppTypography.buttonLabel.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final line = Expanded(
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'o continúa con',
            style: AppTypography.caption.copyWith(
              color: AppColors.darkTextMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        line,
      ],
    );
  }

  Widget _buildSocialButtons(bool isBusy) {
    return Column(
      children: [
        if (Platform.isIOS || Platform.isMacOS) ...[
          SocialLoginButton(
            label: 'Continuar con Apple ID',
            icon: Icons.apple_rounded,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            isLoading: isBusy,
            onPressed: () => ref.read(authProvider.notifier).loginWithApple(),
          ),
          const SizedBox(height: 14),
        ],
        SocialLoginButton(
          label: 'Continuar con Google',
          icon: Icons.g_mobiledata_rounded,
          backgroundColor: AppColors.darkSurfaceElevated,
          textColor: Colors.white,
          borderColor: AppColors.neonPurple.withValues(alpha: 0.55),
          isLoading: isBusy,
          onPressed: () => ref.read(authProvider.notifier).loginWithGoogle(),
        ),
      ],
    );
  }

  Widget _buildSecurityNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 15,
          color: AppColors.neonCyan.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tus tokens se cifran en hardware (AES-256 / Keychain).',
            style: AppTypography.caption.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateAccountLink(bool isBusy) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '¿No tienes cuenta?',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.darkTextSecondary,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: isBusy
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RegistrationScreen(),
                    ),
                  ),
          child: Text(
            'Crear una',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neonPink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Text(
      '© 2026 GymPro Technologies Inc.',
      style: AppTypography.caption,
    );
  }
}
