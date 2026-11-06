import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Glass icons with counter for water tracking. Goal = 8 glasses.
class WaterTracker extends StatelessWidget {
  final int count;
  final int goal;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const WaterTracker({
    super.key,
    required this.count,
    this.goal = 8,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop, color: AppColors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                'Water',
                style: AppTypography.bodyL.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text(
                '$count / $goal glasses',
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Glass icons
          Row(
            children: List.generate(goal, (index) {
              final filled = index < count;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 2,
                    right: index == goal - 1 ? 0 : 2,
                  ),
                  child: Icon(
                    filled ? Icons.water_drop : Icons.water_drop_outlined,
                    color: filled ? AppColors.blue : AppColors.textDisabled,
                    size: 22,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Progress bar
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: goal > 0 ? (count / goal).clamp(0.0, 1.0) : 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove_circle_outline,
                    color: AppColors.textSecondary, size: 28),
              ),
              const SizedBox(width: 12),
              Text(
                '$count',
                style: AppTypography.body.copyWith(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_circle,
                    color: AppColors.blue, size: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
