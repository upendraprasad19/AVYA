import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Personal Records 2×2 grid — matches the handoff
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 229–251).
///
/// Shows the top 4 PRs as a 2×2 grid of `card`-bg tiles with `line2`
/// border. Each tile: mono 8 exercise name + `ok` delta (if available)
/// on a single row, then Fraunces 22 w700 gold tabular numeric + mono
/// 8 unit on the second row. "SEE ALL N" opens the full list sheet
/// (preserved from the pre-port behaviour).
class PrSnapshot extends ConsumerWidget {
  const PrSnapshot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = ref.watch(allExercisePRsProvider);

    if (prs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              size: 16,
              color: AppColors.textDim,
            ),
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

    final top = prs.take(4).toList();
    final hasMore = prs.length > 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, c) {
          final gap = 6.0;
          final width = (c.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final pr in top)
                SizedBox(width: width, child: _PrTile(pr: pr)),
            ],
          );
        }),
        if (hasMore) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showAllPRsSheet(context, prs),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'SEE ALL ${prs.length} \u2192',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
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
              top: Radius.circular(AppRadius.card),
            ),
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
                  AppSpacing.gutter,
                  4,
                  AppSpacing.gutter,
                  12,
                ),
                child: Row(
                  children: [
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
                  separatorBuilder: (_, _) =>
                      Container(height: 1, color: AppColors.line2),
                  itemBuilder: (_, i) {
                    final pr = prs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
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

class _PrTile extends StatelessWidget {
  const _PrTile({required this.pr});
  final ExercisePR pr;

  @override
  Widget build(BuildContext context) {
    // Expect formattedValue like "82.5 kg" or "14 reps". Split into
    // numeric + unit so we can render Fraunces on the number and mono
    // on the unit.
    final parts = pr.formattedValue.split(' ');
    final numeric = parts.isNotEmpty ? parts.first : pr.formattedValue;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pr.exerciseName.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              fontSize: 8,
              color: AppColors.textMute,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  numeric,
                  style: AppTypography.h2.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    letterSpacing: -0.6,
                    height: 1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit.toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 8,
                    color: AppColors.textMute,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
