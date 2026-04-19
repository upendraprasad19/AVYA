import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

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
      return WardCard(
        variant: WardCardVariant.standard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 16, color: AppColors.textDim),
            const SizedBox(width: 10),
            Text(
              'Log workouts to see your PRs here',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    // Always show top 3 only. Full list is in the bottom sheet.
    final visiblePrs = prs.take(3).toList();
    final hasMore = prs.length > 3;

    return WardCard(
      variant: WardCardVariant.standard,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.emoji_events,
                    size: 13, color: AppColors.proGold),
                const SizedBox(width: 6),
                Text(
                  'PERSONAL RECORDS',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.proGold,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                if (hasMore)
                  GestureDetector(
                    onTap: () => _showAllPRsSheet(context, prs),
                    child: Text(
                      'SEE ALL ${prs.length} \u2192',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.line2),

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
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.proGoldTint,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadius.card),
                    bottomRight: Radius.circular(AppRadius.card),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.expand_more,
                        size: 13, color: AppColors.proGold),
                    const SizedBox(width: 4),
                    Text(
                      '${prs.length - 3} MORE PRS',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.proGold,
                        letterSpacing: 2,
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
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.card)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter, 4, AppSpacing.gutter, 12),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events,
                        size: 14, color: AppColors.proGold),
                    const SizedBox(width: 8),
                    Text(
                      'ALL EXERCISE PRS',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    WardChip(
                      label: '${prs.length} EXERCISES',
                      tone: WardChipTone.gold,
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: AppColors.line2),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: prs.length,
                  separatorBuilder: (_, index) =>
                      Container(height: 1, color: AppColors.line2),
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
                            color: AppColors.proGold,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pr.exerciseName,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  pr.formattedDate,
                                  style: AppTypography.monoXs.copyWith(
                                    color: AppColors.textMute,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            pr.formattedValue,
                            style: AppTypography.h3.copyWith(
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
            : const Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            // Slim gold slab
            Container(
              width: 3,
              height: 30,
              color: AppColors.proGold,
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
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pr.formattedDate,
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              pr.formattedValue,
              style: AppTypography.h3.copyWith(
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
