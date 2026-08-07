import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../payment/presentation/providers/payment_provider.dart';
import '../../../payment/presentation/widgets/plan_selector_sheet.dart';
import '../../../qr_access/presentation/providers/qr_access_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

class DynamicAccessQrCard extends ConsumerStatefulWidget {
  const DynamicAccessQrCard({super.key});

  @override
  ConsumerState<DynamicAccessQrCard> createState() => _DynamicAccessQrCardState();
}

class _DynamicAccessQrCardState extends ConsumerState<DynamicAccessQrCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(qrAccessProvider.notifier).startDynamicRefresh());
    
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Al iniciar sesión, la suscripción se refresca de forma asíncrona; el QR se
    // arranca en initState mientras aún carga (isAccessValid=false) y quedaba en
    // "pago requerido" hasta recargar. Escuchamos el acceso: en cuanto pasa a
    // válido, (re)generamos el QR sin recargar.
    ref.listen<bool>(isAccessValidProvider, (prev, next) {
      if (next == true && prev != true) {
        ref.read(qrAccessProvider.notifier).startDynamicRefresh();
      }
    });

    ref.listen<PaymentCheckoutState>(paymentProvider, (previous, next) {
      if (next.status == PaymentCheckoutStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: const Color(0xFFFF2A5F), // Rosa/Rojo
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
            child: CircularProgressIndicator(color: Color(0xFF1EE083)),
          ),
        ),
      ),
      error: (err, _) => _buildInactiveAlertCardAnimated(
        title: 'Acceso Inactivo',
        message: 'No fue posible verificar la vigencia de tu membresía. Revisa tu conexión o pagos.',
        isBusy: false,
      ),
      data: (subscription) {
        if (!subscription.isAccessValid || qrState.status == QrStatus.paymentRequired) {
          return _buildInactiveAlertCardAnimated(
            title: 'Acceso Inactivo',
            message: subscription.status == 'past_due'
                ? 'Tu membresía presenta un adeudo o ha expirado. Para ingresar a los torniquetes, regulariza tu pago.'
                : 'Suscripción cancelada o sin vigencia activa en GymPro.',
            isBusy: paymentState.status == PaymentCheckoutStatus.loading,
          );
        }

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
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1EE083),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ACCESO BIOMÉTRICO',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF1EE083),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'AES-256',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF00D0FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (qrState.status == QrStatus.loading && qrState.qrToken == null)
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF1EE083))),
                )
              else if (qrState.status == QrStatus.error && qrState.qrToken == null)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.refresh_rounded, color: Color(0xFFFFB300), size: 36),
                        const SizedBox(height: 8),
                        Text('Reintentando...', style: GoogleFonts.inter(color: Colors.white)),
                      ],
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: qrState.secondsRemaining / 30.0,
                        strokeWidth: 2,
                        backgroundColor: const Color(0xFF27272A),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D0FF)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Actualiza en ${qrState.secondsRemaining}s',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA1A1AA),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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
        color: const Color(0xFF18181B), // Tarjeta plana
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF27272A), width: 1),
      ),
      child: child,
    );
  }

  Widget _buildInactiveAlertCardAnimated({
    required String title,
    required String message,
    required bool isBusy,
  }) {
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1014), // Fondo rojo súper oscuro (Twine style)
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF3F161E), width: 1), // Borde rojo sutil
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF3F161E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.credit_card_off_rounded, color: Color(0xFFFF2A5F), size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.inter(
                  color: const Color(0xFFE4E4E7),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // Botón Sólido estilo pastilla
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isBusy
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          PlanSelectorSheet.show(context, ref);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1EE083), // Verde Esmeralda (Imagen 1)
                    disabledBackgroundColor: const Color(0xFF27272A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : Text(
                          'REGULARIZAR PAGOS',
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
