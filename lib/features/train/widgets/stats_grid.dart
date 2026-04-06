import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/train_provider.dart';

class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = _loadPRs(ref);
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
            onTap: () => _showAllPRsSheet(context, ref),
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

  /// Reads workout_logs via provider so the grid refreshes after workout completion.
  Map<String, _PRData> _loadPRs(WidgetRef ref) {
    final rawPRs = ref.watch(workoutStatsProvider);
    return rawPRs.map((key, value) => MapEntry(
          key,
          _PRData(
            current: value['current'] ?? 0,
            previous: value['previous'] ?? 0,
          ),
        ));
  }

  void _showAllPRsSheet(BuildContext context, WidgetRef ref) {
    final allPRs = ref.read(allExercisePRsProvider);

    if (allPRs.isEmpty) {
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events,
                        size: 16, color: AppColors.proGold),
                    const SizedBox(width: 8),
                    Text(
                      'ALL EXERCISE PRs',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentTint,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${allPRs.length} exercises',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: AppColors.border),
              // List
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: allPRs.length,
                  separatorBuilder: (_, _) =>
                      Container(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) {
                    final pr = allPRs[i];
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.proGold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pr.exerciseName,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pr.formattedDate,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            pr.formattedValue,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _PRData {
  final double current;
  final double previous;

  const _PRData({required this.current, required this.previous});

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
