import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

/// Personal Records snapshot on the home dashboard.
///
/// Always shows the 3 most recent PRs in a compact vertical list.
/// "See All N" opens a bottom sheet — never expands in-place so the
/// card stays a fixed size regardless of how many exercises the user has.
class PrSnapshot extends ConsumerWidget {
  const PrSnapshot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = ref.watch(allExercisePRsProvider);

    if (prs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(
              'Log workouts to see your PRs here',
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

    // Always show top 3 only. Full list is in the bottom sheet.
    final visiblePrs = prs.take(3).toList();
    final hasMore = prs.length > 3;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.emoji_events,
                    size: 13, color: AppColors.proGold),
                const SizedBox(width: 6),
                Text(
                  'PERSONAL RECORDS',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.proGold,
                  ),
                ),
                const Spacer(),
                if (hasMore)
                  GestureDetector(
                    onTap: () => _showAllPRsSheet(context, prs),
                    child: Text(
                      'See All ${prs.length} →',
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

          ...visiblePrs.asMap().entries.map((entry) {
            final i = entry.key;
            final pr = entry.value;
            final isLast = i == visiblePrs.length - 1 && !hasMore;
            return _PrRow(pr: pr, isLast: isLast);
          }),

          if (hasMore)
            GestureDetector(
              onTap: () => _showAllPRsSheet(context, prs),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.proGoldTint,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadius.cardM),
                    bottomRight: Radius.circular(AppRadius.cardM),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.expand_more,
                        size: 13, color: AppColors.proGold),
                    const SizedBox(width: 4),
                    Text(
                      '${prs.length - 3} more PRs',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.proGold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAllPRsSheet(BuildContext context, List<ExercisePR> prs) {
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
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events,
                        size: 14, color: AppColors.proGold),
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
                        '${prs.length} exercises',
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
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: prs.length,
                  separatorBuilder: (_, index) =>
                      Container(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) {
                    final pr = prs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.proGold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
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

/// A single PR row — compact, matching the "RECENT LOGS" style.
class _PrRow extends StatelessWidget {
  final ExercisePR pr;
  final bool isLast;

  const _PrRow({required this.pr, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            // Slimmer gold bar matches "RECENT LOGS" row density.
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.proGold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pr.exerciseName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    pr.formattedDate,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
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
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
