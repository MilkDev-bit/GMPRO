/// @file lib/features/auth/presentation/widgets/signup_progress_bar.dart
/// @description Encabezado de flujo multi-paso: botón atrás, contador "Paso X de N"
/// y barra segmentada animada con gradiente neón (easeOutCubic).

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class SignupProgressBar extends StatelessWidget {
  final int currentStep; // 0-based
  final int totalSteps;
  final VoidCallback onBack;

  const SignupProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CircleBackButton(onTap: onBack),
            const Spacer(),
            Text(
              'Paso ${currentStep + 1} de $totalSteps',
              style: AppTypography.caption.copyWith(
                color: AppColors.darkTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: List.generate(totalSteps, (index) {
            final bool isActive = index <= currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.primaryGradient : null,
                    color: isActive ? null : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.neonPurple.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CircleBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.2,
            ),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}
