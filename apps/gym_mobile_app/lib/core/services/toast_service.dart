/// @file lib/core/services/toast_service.dart
/// @description Servicio estático centralizado para mostrar Toasts premium (estilo iOS Dynamic Island) con Toastification.

import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class ToastService {
  ToastService._(); // Singleton estático no instanciable

  /// Llave global de navegación para poder mostrar toasts y modales sin requerir un [BuildContext] explícito en controllers.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Retorna el contexto actual de navegación seguro.
  static BuildContext? get _context => navigatorKey.currentContext;

  // ── 1. TOAST DE ÉXITO (Neon Cyan / Green) ──────────────────────────────────
  static void showSuccessToast({
    required String message,
    String title = 'Éxito',
    Duration duration = const Duration(seconds: 4),
  }) {
    _showCustomToast(
      title: title,
      message: message,
      type: ToastificationType.success,
      primaryColor: AppColors.success,
      icon: Icons.check_circle_rounded,
      duration: duration,
    );
  }

  // ── 2. TOAST DE ERROR (Neon Pink / Red) ────────────────────────────────────
  static void showErrorToast({
    required String message,
    String title = 'Atención',
    Duration duration = const Duration(seconds: 5),
  }) {
    _showCustomToast(
      title: title,
      message: message,
      type: ToastificationType.error,
      primaryColor: AppColors.error,
      icon: Icons.error_rounded,
      duration: duration,
    );
  }

  // ── 3. TOAST DE ADVERTENCIA (Neon Amber) ───────────────────────────────────
  static void showWarningToast({
    required String message,
    String title = 'Advertencia',
    Duration duration = const Duration(seconds: 4),
  }) {
    _showCustomToast(
      title: title,
      message: message,
      type: ToastificationType.warning,
      primaryColor: AppColors.warning,
      icon: Icons.warning_rounded,
      duration: duration,
    );
  }

  // ── 4. TOAST INFORMATIVO (Neon Purple / Cyan) ──────────────────────────────
  static void showInfoToast({
    required String message,
    String title = 'Notificación GymPro',
    Duration duration = const Duration(seconds: 4),
  }) {
    _showCustomToast(
      title: title,
      message: message,
      type: ToastificationType.info,
      primaryColor: AppColors.neonCyan,
      icon: Icons.auto_awesome_rounded,
      duration: duration,
    );
  }

  // ── Motor Interno de Renderizado Premium ───────────────────────────────────
  static void _showCustomToast({
    required String title,
    required String message,
    required ToastificationType type,
    required Color primaryColor,
    required IconData icon,
    required Duration duration,
  }) {
    final ctx = _context;
    if (ctx == null) {
      debugPrint('⚠️ [ToastService] No se pudo mostrar el toast porque navigatorKey.currentContext es nulo.');
      return;
    }

    toastification.show(
      context: ctx,
      type: type,
      style: ToastificationStyle.flatColored,
      autoCloseDuration: duration,
      title: Text(
        title,
        style: AppTypography.titleLarge.copyWith(
          fontSize: 15,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      description: Text(
        message,
        style: AppTypography.bodyMedium.copyWith(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      alignment: Alignment.topCenter,
      direction: TextDirection.ltr,
      animationDuration: const Duration(milliseconds: 350),
      animationBuilder: (context, animation, alignment, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.4),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart)),
            child: child,
          ),
        );
      },
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: primaryColor, size: 22),
      ),
      primaryColor: primaryColor,
      backgroundColor: const Color(0xFF161324), // Obsidian dark elevated
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: BorderRadius.circular(24), // Curvas orgánicas de GymPro
      borderSide: BorderSide(
        color: primaryColor.withValues(alpha: 0.5),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: primaryColor.withValues(alpha: 0.25),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      showProgressBar: true,
      progressBarTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: Colors.white12,
        linearMinHeight: 2.5,
      ),
      closeButtonShowType: CloseButtonShowType.onHover,
      closeOnClick: true,
      pauseOnHover: true,
      dragToClose: true,
    );
  }
}
