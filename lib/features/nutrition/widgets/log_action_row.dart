import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// The two side-by-side actions under TODAY'S SUMMARY (founder call 2026-11-01):
/// LOG FOOD (gold, opens the 5-mode LogFoodSheet) and LOG HYDRATION (outlined,
/// opens the hydration sheet). Hydration stays hidden until asked for, so the
/// day's logged foods sit directly under these buttons.
class LogActionRow extends StatelessWidget {
  const LogActionRow({
    super.key,
    required this.onLogFood,
    required this.onLogHydration,
  });

  final VoidCallback onLogFood;
  final VoidCallback onLogHydration;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: _logFood()),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: _logHydration()),
      ],
    );
  }

  Widget _logFood() {
    return GestureDetector(
      key: const ValueKey('log_food_cta'),
      onTap: onLogFood,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.20),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.bgDeep, size: 18),
            const SizedBox(width: 6),
            Text(
              'LOG FOOD',
              style: AppTypography.mono.copyWith(
                color: AppColors.bgDeep,
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logHydration() {
    return GestureDetector(
      key: const ValueKey('log_hydration_cta'),
      onTap: onLogHydration,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.water_drop_outlined, color: AppColors.accent, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'LOG HYDRATION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
