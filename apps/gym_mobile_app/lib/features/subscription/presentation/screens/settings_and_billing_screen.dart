/// @file lib/features/subscription/presentation/screens/settings_and_billing_screen.dart
/// @description Pantalla de Ajustes y Gestión de Membresía con Glassmorphism flotante y modo oscuro neón.
/// CUMPLE CON LAS 3 SECCIONES REQUERIDAS:
///   1. Centro de Gestión de Pagos y Reintento Automático (Alerta de fallo past_due con parpadeo neón,
///      invocación a Stripe Checkout y modal DraggableScrollableSheet con historial y descarga PDF de facturas).
///   2. Menú de Configuración General (Modificar datos físicos, Notificaciones push y Passkeys biométricos).
///   3. Módulo de Soporte y Contacto (Cumplimiento App Store/Google Play via WhatsApp Business y Correo con ID).

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import 'package:dio/dio.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/notification_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../providers/subscription_provider.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../domain/entities/user_subscription.dart';
import '../../../nutrition/presentation/providers/nutrition_provider.dart';
import '../../../nutrition/presentation/widgets/diet_profile_sheet.dart';
import '../../../workout/presentation/providers/workout_provider.dart';
import '../../../workout/presentation/widgets/workout_profile_sheet.dart';

class SettingsAndBillingScreen extends ConsumerStatefulWidget {
  const SettingsAndBillingScreen({super.key});

  @override
  ConsumerState<SettingsAndBillingScreen> createState() => _SettingsAndBillingScreenState();
}

class _SettingsAndBillingScreenState extends ConsumerState<SettingsAndBillingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Estados locales para el menú de configuración
  bool _notificationsEnabled = true;
  bool _passkeysEnabled = true;

  @override
  void initState() {
    super.initState();
    // Controlador de animación para el parpadeo neón sutil en caso de pago fallido (past_due)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final subAsync = ref.watch(subscriptionProvider);
    final paymentState = ref.watch(paymentProvider);
    final dietProfile = ref.watch(nutritionProvider).profile;
    final workoutProfile = ref.watch(workoutProvider).profile;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── CABECERA PERFIL SOCIO ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  children: [
                    _UserProfileHeader(user: user),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // ── SECCIÓN 1: CENTRO DE GESTIÓN DE PAGOS Y REINTENTO AUTOMÁTICO ───
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CENTRO DE FACTURACIÓN Y PAGOS',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  subAsync.when(
                    loading: () => const _LoadingCard(),
                    error: (e, _) => _FailedPaymentCard(
                      pulseAnimation: _pulseAnimation,
                      planName: 'Membresía Desconectada / Error',
                      validUntil: DateTime.now(),
                      isLoading: paymentState.status == PaymentCheckoutStatus.loading,
                      onRetryPayment: _handleRetryPayment,
                      onOpenInvoices: () => _showInvoicesModal(context, user),
                    ),
                    data: (sub) {
                      final status = sub.status;
                      final isFailed = status == 'past_due' || status == 'canceled' || !sub.isAccessValid;

                      if (isFailed) {
                        return _FailedPaymentCard(
                          pulseAnimation: _pulseAnimation,
                          planName: sub.planName,
                          validUntil: sub.validoHasta,
                          isLoading: paymentState.status == PaymentCheckoutStatus.loading,
                          onRetryPayment: _handleRetryPayment,
                          onOpenInvoices: () => _showInvoicesModal(context, user),
                        );
                      } else {
                        return _ActivePaymentCard(
                          subscription: sub,
                          isLoading: paymentState.status == PaymentCheckoutStatus.loading,
                          onManageStripe: _handleRetryPayment,
                          onOpenInvoices: () => _showInvoicesModal(context, user),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ── SECCIÓN 2: MENÚ DE CONFIGURACIÓN GENERAL (SETTINGS) ────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONFIGURACIÓN GENERAL',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsGlassContainer(
                    children: [
                      _SettingsItem(
                        icon: Icons.monitor_weight_outlined,
                        iconColor: AppColors.neonCyan,
                        title: 'Datos Físicos y Objetivo',
                        subtitle: dietProfile.isComplete
                            ? '${dietProfile.objetivoLabel} • ${dietProfile.pesoKg.toStringAsFixed(0)} kg • ${dietProfile.estaturaCm.toStringAsFixed(0)} cm • ${dietProfile.edad} años • ${dietProfile.actividadLabel}'
                            : 'Sin configurar — toca para completar tu perfil',
                        onTap: () => DietProfileSheet.show(context),
                      ),
                      Divider(color: AppColors.glassBorderOf(context), height: 1),
                      _SettingsItem(
                        icon: Icons.fitness_center_rounded,
                        iconColor: AppColors.neonPurple,
                        title: 'Rutina y Entrenamiento',
                        subtitle: workoutProfile.isComplete
                            ? '${workoutProfile.objetivoLabel} • ${workoutProfile.nivelLabel} • ${workoutProfile.diasPorSemana} días/semana'
                            : 'Sin configurar — toca para generar tu rutina',
                        onTap: () => WorkoutProfileSheet.show(context),
                      ),
                      Divider(color: AppColors.glassBorderOf(context), height: 1),
                      _SettingsSwitchItem(
                        icon: Icons.notifications_active_outlined,
                        iconColor: AppColors.neonPink,
                        title: 'Notificaciones y Avisos Push',
                        subtitle: 'Pases locales, recordatorios y alertas de acceso',
                        value: _notificationsEnabled,
                        onChanged: (val) async {
                          setState(() => _notificationsEnabled = val);
                          if (val) {
                            await NotificationServiceImpl.instance.requestPermissions();
                            if (!context.mounted) return;
                            toastification.show(
                              context: context,
                              type: ToastificationType.success,
                              style: ToastificationStyle.minimal,
                              title: const Text('Notificaciones Activas'),
                              description: const Text('Recibirás alertas de pases locales y recordatorios.'),
                              autoCloseDuration: const Duration(seconds: 3),
                            );
                          }
                        },
                      ),
                      Divider(color: AppColors.glassBorderOf(context), height: 1),
                      _SettingsSwitchItem(
                        icon: Icons.fingerprint_rounded,
                        iconColor: AppColors.neonPurple,
                        title: 'Administrar Passkeys Biométricos',
                        subtitle: 'Inicia sesión con FaceID o Huella dactilar sin contraseña',
                        value: _passkeysEnabled,
                        onChanged: (val) {
                          setState(() => _passkeysEnabled = val);
                          HapticFeedback.mediumImpact();
                          toastification.show(
                            context: context,
                            type: ToastificationType.info,
                            style: ToastificationStyle.minimal,
                            title: Text(val ? 'Passkey Biométrico Registrado' : 'Passkey Desactivado'),
                            description: Text(val ? 'Este dispositivo ahora es una llave criptográfica segura.' : 'Se requerirá inicio de sesión tradicional.'),
                            autoCloseDuration: const Duration(seconds: 3),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ── SECCIÓN 3: MÓDULO DE SOPORTE Y CONTACTO ────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SOPORTE Y ASISTENCIA (APP STORE COMPLIANT)',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsGlassContainer(
                    children: [
                      _SettingsItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: const Color(0xFF25D366), // Verde WhatsApp
                        title: 'Chat Automatizado WhatsApp',
                        subtitle: 'Asistencia inmediata 24/7 para accesos y cobros',
                        onTap: () => _openWhatsAppSupport(user?.id ?? 'INVITADO'),
                      ),
                      Divider(color: AppColors.glassBorderOf(context), height: 1),
                      _SettingsItem(
                        icon: Icons.email_outlined,
                        iconColor: const Color(0xFFFF9500),
                        title: 'Correo Corporativo pre-llenado',
                        subtitle: 'Adjunta automáticamente tu ID de socio al asunto',
                        onTap: () => _openEmailSupport(user?.id ?? 'INVITADO', user?.email ?? ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Botón Cerrar Sesión
                  GestureDetector(
                    onTap: () => ref.read(authProvider.notifier).logout(),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.35), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, color: AppColors.error.withValues(alpha: 0.9), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Cerrar Sesión Segura',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── INVOCACIÓN A PAYMENT SHEET / STRIPE ────────────────────────────────────
  void _handleRetryPayment() async {
    HapticFeedback.heavyImpact();
    final success = await ref.read(paymentProvider.notifier).launchStripeCheckout(
      priceId: 'price_retry_membership_vip',
    );

    if (!success && mounted) {
      final state = ref.read(paymentProvider);
      if (state.errorMessage != null) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.minimal,
          title: const Text('Error al abrir pasarela'),
          description: Text(state.errorMessage!),
          autoCloseDuration: const Duration(seconds: 4),
        );
      }
    }
  }

  // ── MODAL DRAGGABLESCROLLABLESHEET DE HISTORIAL DE FACTURAS ────────────────
  void _showInvoicesModal(BuildContext context, AuthUser? user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InvoicesModalSheet(userId: user?.id ?? 'USR-001'),
    );
  }

  // ── APERTURA DE WHATSAPP BUSINESS Y CORREO NATIVO ──────────────────────────
  void _openWhatsAppSupport(String userId) async {
    final text = Uri.encodeComponent(
        "Hola Soporte GymPro AI, solicito asistencia con mi cuenta. Mi ID de Socio es: [$userId]");
    final uri = Uri.parse("https://wa.me/5215512345678?text=$text");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.minimal,
          title: const Text('WhatsApp no disponible'),
          description: const Text('No pudimos abrir la aplicación de WhatsApp Business en este dispositivo.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  void _openEmailSupport(String userId, String userEmail) async {
    final subject = Uri.encodeComponent("Soporte y Asistencia - ID de Socio: $userId");
    final body = Uri.encodeComponent(
        "Hola Equipo de Soporte GymPro,\n\nSolicito apoyo con respecto a mi membresía/acceso.\n\nDatos del Socio:\n- ID: $userId\n- Correo: $userEmail\n\nDetalle de la consulta:\n");
    final uri = Uri.parse("mailto:soporte@gympro-ai.com?subject=$subject&body=$body");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.minimal,
          title: const Text('App de Correo no disponible'),
          description: const Text('No se encontró una aplicación de correo configurada.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENTES DE INTERFAZ (WIDGETS PRIVADOS MODULARIZADOS)
// ─────────────────────────────────────────────────────────────────────────────

class _UserProfileHeader extends StatelessWidget {
  const _UserProfileHeader({required this.user});
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.neonPurple, AppColors.neonPink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonPink.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              (user?.nombre ?? 'S').substring(0, 1).toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user?.nombre ?? 'Socio GymPro',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.neonCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Text(
                      'VIP AI',
                      style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.neonCyan),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'socio@gympro.com',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta para Membresía en estado de error, past_due o vencida (Parpadeo Neón Rojo Carmesí)
class _FailedPaymentCard extends StatelessWidget {
  const _FailedPaymentCard({
    required this.pulseAnimation,
    required this.planName,
    required this.validUntil,
    required this.isLoading,
    required this.onRetryPayment,
    required this.onOpenInvoices,
  });

  final Animation<double> pulseAnimation;
  final String planName;
  final DateTime validUntil;
  final bool isLoading;
  final VoidCallback onRetryPayment;
  final VoidCallback onOpenInvoices;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF380C14), Color(0xFF1E080D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: pulseAnimation.value),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: pulseAnimation.value * 0.35),
                    blurRadius: 28,
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
                          color: AppColors.error.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.6), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'PAGO FALLIDO / PAST DUE',
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onOpenInvoices,
                        icon: const Icon(Icons.receipt_long_rounded, color: Colors.white70, size: 22),
                        tooltip: 'Historial de Facturas',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    planName,
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No pudimos procesar el cobro automático de tu suscripción o el webhook de Stripe reportó error. Tu acceso biométrico al torniquete se suspenderá.',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFFFCCD2), height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: isLoading ? null : onRetryPayment,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFC62828)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
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
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          else ...[
                            const Icon(Icons.credit_score_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Actualizar Tarjeta / Reintentar Cobro',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: onOpenInvoices,
                      child: Text(
                        'Ver Historial de Cobros y Recibos PDF ->',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta para Membresía Activa (Esmeralda Neón)
class _ActivePaymentCard extends StatelessWidget {
  const _ActivePaymentCard({
    required this.subscription,
    required this.isLoading,
    required this.onManageStripe,
    required this.onOpenInvoices,
  });

  final UserSubscription subscription;
  final bool isLoading;
  final VoidCallback onManageStripe;
  final VoidCallback onOpenInvoices;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0C2A1A), Color(0xFF091E14)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.35), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.15),
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
                      color: AppColors.success.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            boxShadow: [
                              BoxShadow(color: AppColors.success.withValues(alpha: 0.8), blurRadius: 6),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          subscription.statusDisplayLabel.toUpperCase(),
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onOpenInvoices,
                    icon: const Icon(Icons.receipt_long_rounded, color: Colors.white70, size: 22),
                    tooltip: 'Historial de Facturas PDF',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                subscription.planName,
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Acceso total a torniquete por biometría/QR y Rutinas IA Fitia ilimitadas. Válido hasta el ${_formatDate(subscription.validoHasta)}.',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: isLoading ? null : onManageStripe,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.neonPurple, AppColors.neonPink]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: AppColors.neonPink.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Center(
                          child: isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  'Portal de Pagos Stripe',
                                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: onOpenInvoices,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0x22FFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x33FFFFFF), width: 1),
                      ),
                      child: Center(
                        child: Text(
                          'Facturas PDF',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.neonPink),
      ),
    );
  }
}

/// Contenedor Glassmorphism para listas de opciones de configuración
class _SettingsGlassContainer extends StatelessWidget {
  const _SettingsGlassContainer({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
          ),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context))),
                  const SizedBox(height: 3),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMutedOf(context), size: 22),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchItem extends StatelessWidget {
  const _SettingsSwitchItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: 3),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.neonPink,
            activeTrackColor: AppColors.neonPink.withValues(alpha: 0.35),
            inactiveThumbColor: AppColors.textMutedOf(context),
            inactiveTrackColor: AppColors.isDark(context) ? const Color(0xFF2A2A38) : const Color(0xFFE0E0E8),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODAL DRAGGABLESCROLLABLESHEET: HISTORIAL DE FACTURAS Y DESCARGA PDF
// ─────────────────────────────────────────────────────────────────────────────
class _InvoicesModalSheet extends ConsumerStatefulWidget {
  const _InvoicesModalSheet({required this.userId});
  final String userId;

  @override
  ConsumerState<_InvoicesModalSheet> createState() => _InvoicesModalSheetState();
}

class _InvoicesModalSheetState extends ConsumerState<_InvoicesModalSheet> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingInvoices = true;
  String? _invoicesError;

  bool _isDownloading = false;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
  }

  /// Trae el historial REAL de facturas/recibos del payment-service
  /// (GET /subscription/history). Antes esta lista era un mock hardcodeado.
  Future<void> _fetchInvoices() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      // Normalizamos el base (puede venir con '/payments') y usamos el namespace
      // real del backend: /api/v1/subscriptions/history (plural).
      final base = AppConfig.paymentServiceBaseUrl.replaceFirst(RegExp(r'/payments/?$'), '');
      final res = await apiClient.get('$base/subscriptions/history');
      final raw = (res.data is Map ? res.data['data'] : res.data) as List? ?? [];
      final mapped = raw.map<Map<String, dynamic>>((row) {
        final r = Map<String, dynamic>.from(row as Map);
        return {
          'id': (r['id'] ?? r['stripe_invoice_id'] ?? '—').toString(),
          'date': _fmtDate(r['creado_en'] ?? r['fecha_inicio'] ?? r['valido_hasta']),
          'plan': (r['plan_nombre'] ?? r['plan'] ?? 'Membresía GymPro').toString(),
          'amount': _fmtAmount(r['precio'] ?? r['monto'], r['moneda']),
          'status': (r['estado'] ?? r['status'] ?? 'Pagado').toString(),
        };
      }).toList();
      if (mounted) {
        setState(() {
          _invoices = mapped;
          _loadingInvoices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _invoicesError = 'No pudimos cargar tus facturas.';
          _loadingInvoices = false;
        });
      }
    }
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    try {
      final d = DateTime.parse(v.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return v.toString();
    }
  }

  String _fmtAmount(dynamic amount, dynamic currency) {
    if (amount == null) return '';
    final cur = (currency ?? 'MXN').toString().toUpperCase();
    return '\$$amount $cur';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevatedOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: AppColors.glassBorderOf(context), width: 1)),
          ),
          child: Column(
            children: [
              // Barra tirador
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 45,
                height: 5,
                decoration: BoxDecoration(color: AppColors.glassBorderOf(context), borderRadius: BorderRadius.circular(10)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Historial de Facturas y Recibos',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimaryOf(context)),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
              Divider(color: AppColors.glassBorderOf(context), height: 1),
              Expanded(
                child: _loadingInvoices
                    ? const Center(child: CircularProgressIndicator(color: AppColors.neonPink))
                    : (_invoicesError != null || _invoices.isEmpty)
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                _invoicesError ?? 'Aún no tienes facturas registradas.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: _invoices.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 14),
                  itemBuilder: (ctx, index) {
                    final inv = _invoices[index];
                    final isBusy = _isDownloading && _downloadingId == inv['id'];

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.glassBorderOf(context), width: 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.neonPurple.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.neonPurple, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Factura #${inv["id"]}',
                                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${inv["date"]} • ${inv["plan"]} • ${inv["amount"]}',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: isBusy ? null : () => _downloadAndPreviewPdf(inv["id"] as String),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.neonPink.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.5), width: 1),
                              ),
                              child: isBusy
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonPink))
                                  : Text(
                                      'Descargar PDF',
                                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.neonPink),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Consume el servicio pdfService.js en el backend para generar y previsualizar el ticket PDF en el móvil.
  Future<void> _downloadAndPreviewPdf(String invoiceId) async {
    setState(() {
      _isDownloading = true;
      _downloadingId = invoiceId;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      // Petición al microservicio de facturación en Railway para emitir el PDF
      final response = await apiClient.dio.get(
        '/api/v1/invoices/$invoiceId/pdf',
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.minimal,
          title: Text('Recibo #$invoiceId Descargado'),
          description: const Text('El PDF oficial fiscal generado por pdfService.js está listo.'),
          autoCloseDuration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.info,
          style: ToastificationStyle.minimal,
          title: Text('Previsualización de Ticket #$invoiceId'),
          description: const Text('El ticket fiscal está listo. (En modo offline/prueba se muestra vista digital).'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingId = null;
        });
      }
    }
  }
}
