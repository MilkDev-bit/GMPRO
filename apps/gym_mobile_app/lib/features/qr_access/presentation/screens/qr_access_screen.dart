/// @file lib/features/qr_access/presentation/screens/qr_access_screen.dart
/// @description Pantalla de acceso biométrico dedicada — muestra el QR dinámico a pantalla completa
/// con un fondo de efecto bokeh animado y el código de acceso grande para facilitar el escaneo en torniquete.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/qr_access_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

class QrAccessScreen extends ConsumerWidget {
  const QrAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);
    final qrState = ref.watch(qrAccessProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Fondo bokeh/glow
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x268B3FE0), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x1FFF4D8F), Colors.transparent],
                ),
              ),
            ),
          ),

          // Contenido principal
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'ACCESO BIOMÉTRICO',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu Pasaporte Digital',
                    style: AppTypography.displayMedium,
                  ),
                  const SizedBox(height: 6),
                  subAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (sub) {
                      final s = sub as dynamic;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (s.isAccessValid as bool? ?? false)
                                  ? AppColors.success
                                  : AppColors.error,
                              boxShadow: [
                                BoxShadow(
                                  color: ((s.isAccessValid as bool? ?? false)
                                          ? AppColors.success
                                          : AppColors.error)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.statusDisplayLabel as String? ?? 'Verificando...',
                            style: AppTypography.bodyMedium.copyWith(
                              color: (s.isAccessValid as bool? ?? false)
                                  ? AppColors.success
                                  : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Tarjeta de QR centrada
                  Expanded(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: const Color(0xCC151226),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonPink.withValues(alpha: 0.12),
                                  blurRadius: 40,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _buildQrContent(qrState),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text(
                    'Presenta este código en la lectora del torniquete',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: 120), // Padding para barra flotante
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent(QrAccessState qrState) {
    switch (qrState.status) {
      case QrStatus.initial:
      case QrStatus.loading:
        return const _QrLoadingState();
      case QrStatus.error:
      case QrStatus.paymentRequired:
        return const _QrErrorState();
      case QrStatus.active:
        if (qrState.qrToken == null) return const _QrLoadingState();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: qrState.qrToken!.token,
                version: QrVersions.auto,
                size: 200,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0A0912),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0A0912),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Válido por ${qrState.secondsRemaining} segundos',
              style: AppTypography.caption.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    }
  }
}

class _QrLoadingState extends StatelessWidget {
  const _QrLoadingState();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.neonCyan.withValues(alpha: 0.8)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Generando código seguro...', style: AppTypography.caption),
      ],
    );
  }
}

class _QrErrorState extends StatelessWidget {
  const _QrErrorState();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: AppColors.error, size: 48),
        const SizedBox(height: 12),
        Text('Error al generar el QR', style: AppTypography.caption),
      ],
    );
  }
}
