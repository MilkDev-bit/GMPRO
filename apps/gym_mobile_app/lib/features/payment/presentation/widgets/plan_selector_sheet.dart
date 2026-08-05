/// @file lib/features/payment/presentation/widgets/plan_selector_sheet.dart
/// @description Hoja modal para elegir entre los 3 planes (Mensual / Trimestral /
/// Anual). Al tocar un plan lanza el Stripe Checkout con ese `plan`; el backend
/// resuelve el Stripe Price ID real desde su env (STRIPE_PRICE_ID_*).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/payment_provider.dart';

class _Plan {
  final String key;    // debe coincidir con el backend: mensual | trimestral | anual
  final String name;
  final String price;  // SOLO display — EDITA para que coincida con tus precios de Stripe
  final String period;
  final String note;
  final bool recommended;
  const _Plan(this.key, this.name, this.price, this.period, this.note,
      {this.recommended = false});
}

// NOTA: estos precios son SOLO de presentación. Ajústalos para que reflejen los
// importes reales configurados en tus Stripe Prices (el cobro lo define Stripe).
const List<_Plan> _kPlans = [
  _Plan('mensual', 'Mensual', '\$499', '/mes', 'Flexibilidad total, cancela cuando quieras'),
  _Plan('trimestral', 'Trimestral', '\$1,299', '/3 meses', 'Ahorra ~13% vs mensual'),
  _Plan('anual', 'Anual', '\$3,999', '/año', 'Ahorra ~33% — el mejor valor', recommended: true),
];

class PlanSelectorSheet extends ConsumerWidget {
  const PlanSelectorSheet({super.key});

  /// Abre el selector de planes como hoja modal.
  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const PlanSelectorSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(paymentProvider).isLoading;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            Text('Elige tu plan', style: AppTypography.titleLarge.copyWith(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              'Desbloquea el coaching con IA, la dieta y el acceso a torniquetes.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            ..._kPlans.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PlanCard(
                  plan: p,
                  busy: busy,
                  onTap: () async {
                    final ok = await ref
                        .read(paymentProvider.notifier)
                        .launchStripeCheckout(priceId: p.key);
                    if (ok && context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Pago seguro procesado por Stripe',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool busy;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = plan.recommended ? AppColors.neonPink : AppColors.neonCyan;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: plan.recommended
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.06),
              width: plan.recommended ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.name, style: AppTypography.titleLarge.copyWith(fontSize: 17)),
                        if (plan.recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: accent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'Recomendado',
                              style: AppTypography.caption.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.note,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    plan.price,
                    style: AppTypography.titleLarge.copyWith(fontSize: 20, color: Colors.white),
                  ),
                  Text(
                    plan.period,
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
