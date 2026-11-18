// lib/features/profile/widgets/weight_projection_callout.dart
//
// The one-line callout under the Weekly Report's weight chart. Extracted from
// `ReportsScreen._buildProjectionCallout` (OI-518) so it renders from explicit inputs
// and a test can pump it. WHAT it says is decided by the pure
// `projectionCalloutKind` (`target_weight_check.dart`, the one home of the goal /
// target rules); this widget only draws each kind. A Maintain goal gets a distance
// line (`onTarget` / `offTarget`), never a trend verdict or a date.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/weight_callout_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';

class WeightProjectionCallout extends StatelessWidget {
  const WeightProjectionCallout({
    super.key,
    required this.entries,
    required this.targetWeight,
    required this.goal,
    this.now,
  });

  /// Weigh-ins, oldest first: `{'date': 'YYYY-MM-DD', 'weight_kg': num}`.
  final List<Map<String, dynamic>> entries;

  /// The profile's `target_weight_kg` (the caller shows the callout only when > 0).
  final double targetWeight;

  /// The profile's `primary_goal`. REQUIRED, no default: a call site that forgets it
  /// would read every goal as "wants to gain" again (the OI-518 bug).
  final String goal;

  /// The clock of the date sentence (tests inject it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (entries.length < 2) return const SizedBox();
    final first = entries.first;
    final last = entries.last;
    final firstDate = DateTime.tryParse(first['date'] as String? ?? '');
    final lastDate = DateTime.tryParse(last['date'] as String? ?? '');
    if (firstDate == null || lastDate == null) return const SizedBox();
    final firstW = (first['weight_kg'] as num).toDouble();
    final lastW = (last['weight_kg'] as num).toDouble();
    final weeksDiff = lastDate.difference(firstDate).inDays / 7.0;

    final kind = projectionCalloutKind(
      goal: goal,
      firstW: firstW,
      lastW: lastW,
      weeksDiff: weeksDiff,
      target: targetWeight,
    );

    // Exhaustive, no default: a kind added later is an analyzer error here.
    switch (kind) {
      case ProjectionCalloutKind.none:
        return const SizedBox();
      case ProjectionCalloutKind.adjust:
        return _adjustRow();
      case ProjectionCalloutKind.reached:
        return _reachedRow();
      case ProjectionCalloutKind.eta:
        return _etaRow(firstW: firstW, lastW: lastW, weeksDiff: weeksDiff);
      case ProjectionCalloutKind.onTarget:
        return _onTargetRow(lastW);
      case ProjectionCalloutKind.offTarget:
        return _offTargetRow(lastW);
    }
  }

  // Cut / Build only (a Maintain goal never reaches `adjust`). The diet / nutrition
  // word keys off the same `goal.contains('lose')` test the pure rule uses.
  Widget _adjustRow() {
    final wantsLose = goal.contains('lose');
    return Row(
      children: [
        Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Adjust your ${wantsLose ? "diet" : "nutrition"} to stay on track',
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.warn),
          ),
        ),
      ],
    );
  }

  Widget _reachedRow() {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Text(
          'You\'ve reached your goal weight!',
          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.ok),
        ),
      ],
    );
  }

  // `weeklyRate` is never 0 here: `projectionCalloutKind` returns `none` for a flat
  // series before the date sentence.
  Widget _etaRow({
    required double firstW,
    required double lastW,
    required double weeksDiff,
  }) {
    final weeklyRate = (lastW - firstW) / weeksDiff;
    final remaining = targetWeight - lastW;
    final weeksToGo = (remaining / weeklyRate).abs().ceil();
    final targetDate = (now ?? DateTime.now()).add(Duration(days: weeksToGo * 7));
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateLabel = '${monthNames[targetDate.month - 1]} ${targetDate.year}';

    return Row(
      children: [
        Icon(Icons.trending_down, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'At current rate, you\'ll reach ${targetWeight.toStringAsFixed(0)}kg in ~$weeksToGo weeks (around $dateLabel)',
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.ok),
          ),
        ),
      ],
    );
  }

  // Maintain, inside the window: where the last weigh-in sits, no date, no verdict.
  Widget _onTargetRow(double lastW) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            WeightCalloutCopy.onTargetLine(
              gapTenths: weightGapTenths(lastW, targetWeight),
              target: targetWeight,
            ),
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.ok),
          ),
        ),
      ],
    );
  }

  // Maintain, beyond the window: how far and on which side, no date.
  Widget _offTargetRow(double lastW) {
    return Row(
      children: [
        Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            WeightCalloutCopy.offTargetLine(
              gapTenths: weightGapTenths(lastW, targetWeight),
              target: targetWeight,
            ),
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.warn),
          ),
        ),
      ],
    );
  }
}
