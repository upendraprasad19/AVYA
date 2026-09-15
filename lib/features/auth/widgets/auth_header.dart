import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Compact letterhead for auth sub-views (email form, phone OTP, forgot
/// password, signup form). Welcome retains full hero — only sub-views use this.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: GestureDetector(
                key: const ValueKey('auth-header-back'),
                onTap: onBack,
                child: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Container(
              key: const ValueKey('auth-header-seal'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 1.5),
                color: AppColors.bgDeep,
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/avya_icon.png',
                width: 22,
                height: 22,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 1,
                  color: AppColors.accent.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTypography.titleL.copyWith(
                    fontSize: 22,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
