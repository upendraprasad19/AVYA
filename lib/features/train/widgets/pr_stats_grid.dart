import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// 2x2 grid of personal record stat cards.
class PrStatsGrid extends StatelessWidget {
  const PrStatsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _PrItem(label: 'Bench Press', value: '70kg', emoji: '\u{1f3c6}'),
            _PrItem(label: 'Squat', value: '90kg', emoji: '\u{1f3c6}'),
            _PrItem(label: 'Deadlift', value: '100kg', emoji: '\u{1f3c6}'),
          ],
        ),
      ),
    );
  }
}

class _PrItem extends StatelessWidget {
  final String label;
  final String value;
  final String emoji;

  const _PrItem({
    required this.label,
    required this.value,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        children: [
          Text(
            '$emoji $value',
            style: AppTypography.bodyL.copyWith(fontWeight: FontWeight.w900, color: AppColors.accent),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTypography.body.copyWith(fontSize: 9, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
