import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/home/providers/pr_series_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import 'pr_trend_sheet.dart';

/// Personal Records 2×2 grid — matches the handoff
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 229–251).
///
/// Shows the top 4 PRs as a 2×2 grid of `card`-bg tiles with `line2`
/// border. Each tile: mono 8 exercise name + `ok` delta (if available)
/// on a single row, then Fraunces 22 w700 gold tabular numeric + mono
/// 8 unit on the second row. "SEE ALL N" opens the full list sheet
/// (preserved from the pre-port behaviour).
///
/// Each tile and each list row carries a sparkline of the exercise's best
/// value per workout day (`exercisePrSeriesProvider`) once it has two days of
/// history, and opens the full trend sheet on tap.
class PrSnapshot extends ConsumerWidget {
  const PrSnapshot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prs = ref.watch(allExercisePRsProvider);
    final seriesByName = ref.watch(exercisePrSeriesProvider);

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
                SizedBox(
                  width: width,
                  child: _PrTile(
                    pr: pr,
                    series: _seriesOf(seriesByName, pr),
                    onTap: () => showPrTrendSheet(
                      context,
                      pr: pr,
                      series: _seriesOf(seriesByName, pr),
                    ),
                  ),
                ),
            ],
          );
        }),
        if (hasMore) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showAllPRsSheet(context, prs, seriesByName),
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

  static ExercisePrSeries _seriesOf(
          Map<String, ExercisePrSeries> byName, ExercisePR pr) =>
      byName[exercisePrNameKey(pr.exerciseName)] ?? ExercisePrSeries.empty;

  void _showAllPRsSheet(
    BuildContext context,
    List<ExercisePR> prs,
    Map<String, ExercisePrSeries> seriesByName,
  ) {
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
                    Expanded(
                      child: Text(
                        'ALL EXERCISE PRS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textPrimary,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                    final series = _seriesOf(seriesByName, pr);
                    return _PrListRow(
                      pr: pr,
                      series: series,
                      onTap: () =>
                          showPrTrendSheet(context, pr: pr, series: series),
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

/// The values a sparkline draws: the personal record AS OF each logged day (a
/// running best, so it never dips), or an empty list when the history is too
/// short to be a trend (fewer than two logged days).
List<double> prSparkValues(ExercisePrSeries series) =>
    series.points.length >= 2 ? prRunningBest(series.points) : const <double>[];

/// Below this tile width, or above this text scale, a tile keeps today's
/// layout with no sparkline (the number must stay readable).
const double kPrTileSparkMinWidth = 150;
const double kPrTileSparkMaxTextScale = 1.3;

String _prSemantics(ExercisePR pr) =>
    '${pr.exerciseName} personal record, ${pr.formattedValue}. Show trend';

class _PrListRow extends StatelessWidget {
  const _PrListRow({
    required this.pr,
    required this.series,
    required this.onTap,
  });
  final ExercisePR pr;
  final ExercisePrSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spark = prSparkValues(series);
    return Semantics(
      button: true,
      label: _prSemantics(pr),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                if (spark.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  WardSpark(data: spark, width: 64, height: 22, step: true),
                  const SizedBox(width: 12),
                ],
                Text(
                  pr.formattedValue,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrTile extends StatelessWidget {
  const _PrTile({
    required this.pr,
    required this.series,
    required this.onTap,
  });
  final ExercisePR pr;
  final ExercisePrSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Expect formattedValue like "82.5 kg" or "14 reps". Split into
    // numeric + unit so we can render Fraunces on the number and mono
    // on the unit.
    final parts = pr.formattedValue.split(' ');
    final numeric = parts.isNotEmpty ? parts.first : pr.formattedValue;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final spark = prSparkValues(series);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Semantics(
      button: true,
      label: _prSemantics(pr),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line2),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: LayoutBuilder(builder: (context, c) {
                // The sparkline sits in the NUMBER row, so the name keeps the
                // tile's full width. The +26 restores the padding and border
                // this LayoutBuilder sits inside.
                final showSpark = spark.isNotEmpty &&
                    c.maxWidth + 26 >= kPrTileSparkMinWidth &&
                    textScale <= kPrTileSparkMaxTextScale;
                return Column(
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
                    if (showSpark)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: _number(numeric, unit)),
                          const SizedBox(width: 8),
                          WardSpark(
                              data: spark, width: 40, height: 22, step: true),
                        ],
                      )
                    else
                      _number(numeric, unit),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _number(String numeric, String unit) => Row(
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
      );
}
