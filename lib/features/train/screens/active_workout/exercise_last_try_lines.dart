// The LAST / TRY lines under an exercise's header (Batch M2b Task 2). Moved out of
// the card so the tile-led header and the thumb header can both place them; the
// content is the card's old `Builder`, plus an ellipsis on TRY (a bare `Text`
// before) and a line cap on LAST, because the tile layout gives them a column
// of about 165 dp (126 dp at 320 dp).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../../providers/train_provider.dart';

/// "LAST: 50.0KG × 10 REPS" and "TRY: 52.5KG × 10" for [exerciseName].
///
/// [showTry] is the caller's "never shame" gate: ⑦(b) + ⑥ 6-B suppress the TRY
/// directive whenever any session cut is active (the effective load factor is
/// below 1.0), because "TRY: +2.5kg" would contradict the reduced prefill. The
/// factual LAST line stays. The card owns that decision (it holds the data), so
/// the gate arrives as a plain bool and BOTH header layouts pass the same one.
class ExerciseLastTryLines extends ConsumerWidget {
  const ExerciseLastTryLines({
    super.key,
    required this.exerciseName,
    required this.showTry,
    required this.fallbackReps,
    this.lastMaxLines = 1,
    this.inline = false,
  });

  final String exerciseName;
  final bool showTry;

  /// Reps shown on the TRY line when the history carries none.
  final String fallbackReps;

  /// The header column passes 2: "LAST: 60.0KG × 8 REPS" is about 152 dp of the
  /// 166 dp column and would lose "REPS" from about 1.1x text scale.
  final int lastMaxLines;

  /// The logging viewer lays the two lines side by side when they fit (a
  /// `Wrap`) and each row takes only its own width; the card keeps them
  /// stacked, each row filling the column.
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPerf = ref.watch(lastPerformanceProvider(exerciseName));
    if (!lastPerf.hasData) return const SizedBox.shrink();

    final children = <Widget>[];

    // "Last: 50.0kg × 10 reps" line
    if (lastPerf.lastWeight != null && lastPerf.lastWeight! > 0) {
      children.add(Padding(
        key: const Key('exercise-last-line'),
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
          children: [
            const Icon(Icons.history, size: 10, color: AppColors.textDim),
            const SizedBox(width: 3),
            // Flexible + ellipsis: at 320 dp and a large font this line
            // overflowed (flip R4A-03).
            Flexible(
              child: Text(
                'LAST: ${lastPerf.lastWeight!.toStringAsFixed(1)}KG × ${lastPerf.lastReps ?? '?'} REPS',
                maxLines: lastMaxLines,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    // "Try: 52.5kg × 10" suggestion line, suppressed by [showTry].
    if (lastPerf.suggestedWeight != null &&
        lastPerf.suggestedWeight! > 0 &&
        showTry) {
      children.add(Padding(
        key: const Key('exercise-try-line'),
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
          children: [
            const Icon(Icons.arrow_upward, size: 10, color: AppColors.accent),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                'TRY: ${lastPerf.suggestedWeight!.toStringAsFixed(1)}KG × ${lastPerf.lastReps ?? fallbackReps}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (inline) {
      return Wrap(spacing: 16, children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
