/// @file lib/features/home/presentation/widgets/dynamic_access_qr_card.dart
/// @description Tarjeta visual que muestra el QR de acceso rotativo o la alerta "Acceso Inactivo".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../../qr_access/presentation/providers/qr_access_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

class DynamicAccessQrCard extends ConsumerStatefulWidget {
  const DynamicAccessQrCard({super.key});

  @override
  ConsumerState<DynamicAccessQrCard> createState() => _DynamicAccessQrCardState();
}

class _DynamicAccessQrCardState extends ConsumerState<DynamicAccessQrCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(qrAccessProvider.notifier).startDynamicRefresh());
  }

  @override
  Widget build(BuildContext context) {
    // Escuchar el estado de pago para mostrar errores al abrir Stripe si ocurren
    ref.listen<PaymentCheckoutState>(paymentProvider, (previous, next) {
      if (next.status == PaymentCheckoutStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    final subAsync = ref.watch(subscriptionProvider);
    final qrState = ref.watch(qrAccessProvider);
    final paymentState = ref.watch(paymentProvider);

    return subAsync.when(
      loading: () => _buildCardSurface(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(color: AppColors.neonPink),
          ),
        ),
      ),
      error: (err, _) => _buildInactiveAlertCard(
        title: 'Acceso Inactivo',
        message: 'No fue posible verificar la vigencia de tu membresía. Revisa tu conexión o pagos.',
        isBusy: false,
      ),
      data: (subscription) {
        // ── CASO 1: SUSCRIPCIÓN INACTIVA (past_due / canceled) ───────────────
        if (!subscription.isAccessValid || qrState.status == QrStatus.paymentRequired) {
          return _buildInactiveAlertCard(
            title: 'Acceso Inactivo',
            message: subscription.status == 'past_due'
                ? 'Tu membresía presenta un adeudo o ha expirado. Para ingresar a los torniquetes y utilizar la Inteligencia Artificial, regulariza tu pago.'
                : 'Suscripción cancelada o sin vigencia activa en GymPro.',
            isBusy: paymentState.status == PaymentCheckoutStatus.loading,
          );
        }

        // ── CASO 2: SUSCRIPCIÓN ACTIVA & QR DINÁMICO DE 30s ──────────────────
        return _buildCardSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ACCESO BIOMÉTRICO QR',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'AES-256 Dinámico',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.neonCyan,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (qrState.status == QrStatus.loading && qrState.qrToken == null)
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator(color: AppColors.neonCyan)),
                )
              else if (qrState.status == QrStatus.error && qrState.qrToken == null)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.refresh_rounded, color: AppColors.warning, size: 36),
                        const SizedBox(height: 8),
                        Text('Reintentando conexión...', style: AppTypography.bodyMedium),
                      ],
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonCyan.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrState.qrToken?.token ?? 'GYMPRO_STUB_${DateTime.now().second}',
                    version: QrVersions.auto,
                    size: 190.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: qrState.secondsRemaining / 30.0,
                        strokeWidth: 2.5,
                        backgroundColor: AppColors.surfaceElevated,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonCyan),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Se actualiza en ${qrState.secondsRemaining}s',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardSurface({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInactiveAlertCard({
    required String title,
    required String message,
    required bool isBusy,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF241320),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.error, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.gpp_bad_rounded, color: AppColors.error, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(isBusy ? 'Iniciando Stripe...' : 'Regularizar Membresía (Stripe)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: isBusy
                  ? null
                  : () {
                      ref.read(paymentProvider.notifier).launchStripeCheckout();
                    },
            ),
          ),
        ],
      ),
    );
  }
}
