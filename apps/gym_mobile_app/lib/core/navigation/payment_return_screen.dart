/// @file lib/core/navigation/payment_return_screen.dart
/// @description Vista de confirmación tras el retorno de Stripe (deep link).
/// Recibe los query params ya extraídos por GoRouter y dispara el feedback de
/// éxito (sonido + háptica + Lottie).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../animations/lottie_view.dart';
import '../services/sound_manager.dart';

class PaymentReturnScreen extends StatefulWidget {
  const PaymentReturnScreen({super.key, this.clientSecret, this.status});

  /// payment_intent_client_secret inyectado por Stripe (para verificar contra
  /// el backend si se desea; aquí no se expone al usuario).
  final String? clientSecret;

  /// redirect_status de Stripe: 'succeeded' | 'processing' | 'failed' | null.
  final String? status;

  bool get _isSuccess =>
      status == null || status == 'succeeded'; // null = flujo optimista de éxito

  @override
  State<PaymentReturnScreen> createState() => _PaymentReturnScreenState();
}

class _PaymentReturnScreenState extends State<PaymentReturnScreen> {
  @override
  void initState() {
    super.initState();
    // Feedback sensorial una sola vez, al montar la vista de retorno.
    if (widget._isSuccess) {
      SoundManager.playSuccess();
    } else {
      SoundManager.playError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget._isSuccess;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: ok
                      ? LottieView(
                          asset: 'assets/lottie/success.json',
                          repeat: false,
                          fallback: const Icon(Icons.check_circle_rounded,
                              color: Colors.greenAccent, size: 120),
                        )
                      : const Icon(Icons.error_rounded,
                          color: Colors.redAccent, size: 120),
                ),
                const SizedBox(height: 16),
                Text(
                  ok ? '¡Pago confirmado!' : 'No se pudo completar el pago',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  ok
                      ? 'Tu membresía ya está activa.'
                      : 'Vuelve a intentarlo o contacta a soporte.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  // Navegación declarativa: volvemos al home limpiando el stack.
                  onPressed: () => context.go('/'),
                  child: const Text('Ir al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
