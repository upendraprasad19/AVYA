import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../repositories/workout_repository.dart';

class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final prs = _loadPRs();
    final hasData = prs.values.any((pr) => pr.current > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR STATS',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.inlineGap),

          if (!hasData)
            _buildNoDataAlert()
          else ...[
            // 2×2 grid
            Row(
              children: [
                Expanded(child: _StatCard.fromPR('🏋️', 'BENCH PRESS', prs['bench']!)),
                const SizedBox(width: AppSpacing.inlineGap),
                Expanded(child: _StatCard.fromPR('🏋️', 'SQUAT', prs['squat']!)),
              ],
            ),
            const SizedBox(height: AppSpacing.inlineGap),
            Row(
              children: [
                Expanded(child: _StatCard.fromPR('🏋️', 'DEADLIFT', prs['deadlift']!)),
                const SizedBox(width: AppSpacing.inlineGap),
                Expanded(child: _StatCard.fromPR('💪', 'OVERHEAD PRESS', prs['ohp']!)),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // View All Exercise PRs button
          GestureDetector(
            onTap: () {
              if (!hasData) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Start logging workouts to see your PRs!',
                      style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: Colors.black),
                    ),
                    backgroundColor: AppColors.accent,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
                return;
              }
              // TODO: Navigate to all PRs screen
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  'View All Exercise PRs \u2192',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataAlert() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            '\u{1F4CA}',
            style: GoogleFonts.getFont('DM Sans', fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            'No stats yet',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete your first workout to start tracking PRs',
            textAlign: TextAlign.center,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Reads workout_logs via WorkoutRepository to find PRs for the 4 key lifts.
  Map<String, _PRData> _loadPRs() {
    final rawPRs = WorkoutRepository.instance.loadKeyLiftPRs();
    return rawPRs.map((key, value) => MapEntry(
          key,
          _PRData(
            current: value['current'] ?? 0,
            previous: value['previous'] ?? 0,
          ),
        ));
  }
}

class _PRData {
  final double current;
  final double previous;

  const _PRData({required this.current, required this.previous});
  factory _PRData.empty() => const _PRData(current: 0, previous: 0);

  String get changeText {
    if (current <= 0) return 'No data yet';
    final diff = current - previous;
    if (diff > 0 && previous > 0) return '\u2191 ${diff.toStringAsFixed(1)}kg this month';
    if (previous > 0) return 'Last: ${previous.toStringAsFixed(0)}kg';
    return 'First logged!';
  }

  Color get changeColor {
    if (current <= 0) return AppColors.textSecondary;
    final diff = current - previous;
    if (diff > 0 && previous > 0) return AppColors.green;
    return AppColors.textSecondary;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.change,
    required this.changeColor,
  });

  final String emoji;
  final String label;
  final String value;
  final String change;
  final Color changeColor;

  factory _StatCard.fromPR(String emoji, String label, _PRData pr) {
    return _StatCard(
      emoji: emoji,
      label: label,
      value: pr.current > 0 ? '${pr.current.toStringAsFixed(0)} kg' : '— kg',
      change: pr.changeText,
      changeColor: pr.changeColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji  $label',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: changeColor,
            ),
          ),
        ],
      ),
    );
  }
}
