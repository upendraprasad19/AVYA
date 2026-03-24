import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

/// Personal Records snapshot — 3-column grid: bench, squat, deadlift.
/// Reads from Hive workout logs. Shows soft "no data" state when empty.
class PrSnapshot extends StatelessWidget {
  const PrSnapshot({super.key});

  @override
  Widget build(BuildContext context) {
    final prs = _loadPRs();
    final hasData = prs.values.any((v) => v > 0);

    if (!hasData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '\u{1F3CB}',
              style: GoogleFonts.getFont('DM Sans', fontSize: 16),
            ),
            const SizedBox(width: 8),
            Text(
              'Log workouts to see your PRs here',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _PrItem(
              emoji: '\u{1F3C6}',
              value: prs['bench']! > 0 ? '${prs['bench']!.round()}kg' : '—',
              label: 'Bench Press',
            ),
            _PrItem(
              emoji: '\u{1F3C6}',
              value: prs['squat']! > 0 ? '${prs['squat']!.round()}kg' : '—',
              label: 'Squat',
            ),
            _PrItem(
              emoji: '\u{1F3C6}',
              value: prs['deadlift']! > 0 ? '${prs['deadlift']!.round()}kg' : '—',
              label: 'Deadlift',
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _loadPRs() {
    final rawPRs = WorkoutRepository.instance.loadKeyLiftPRs();
    return {
      'bench': rawPRs['bench']?['current'] ?? 0,
      'squat': rawPRs['squat']?['current'] ?? 0,
      'deadlift': rawPRs['deadlift']?['current'] ?? 0,
    };
  }
}

class _PrItem extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;

  const _PrItem({
    required this.emoji,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$emoji $value',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 9,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
