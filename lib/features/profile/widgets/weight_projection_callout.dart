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
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';

/// A Maintain line says "as of `date`" when the last weigh-in is MORE than this many
/// days old (founder 2026-11-19): the distance is true of that day, not of today.
const int kMaintainStaleAfterDays = 7;

/// A `YYYY-MM-DD` date key as a UTC calendar date (no clock, no zone, no DST), or
/// null for anything else: the pattern is anchored and the parsed date must round
/// trip, so `2026-02-31`, `20261118`, `2026-11-18T10:00:00` and ` 2026-11-18` are null.
/// (`DateTime.tryParse` is local and lenient, and rolls `2026-02-31` over to March.)
DateTime? parseDateKeyUtc(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime.utc(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}

/// The Maintain lines' staleness suffix: empty unless the last weigh-in
/// ([lastDateKey], an IST date key) is more than [kMaintainStaleAfterDays] days
/// before today's IST date. Today is `istDateStr(now)` (the one IST conversion; never
/// `istNow()`, which is already shifted), both days are compared as UTC calendar
/// dates so a DST zone cannot move the count, and a future or unreadable key draws no
/// suffix.
String maintainAsOfSuffix({required String lastDateKey, required DateTime now}) {
  final last = parseDateKeyUtc(lastDateKey);
  final today = parseDateKeyUtc(istDateStr(now));
  if (last == null || today == null) return '';
  if (today.difference(last).inDays <= kMaintainStaleAfterDays) return '';
  return WeightCalloutCopy.asOfSuffix(lastDay: last, today: today);
}

/// The callout as the Weekly Report's weight card places it: reads the goal and the target
/// from the PROFILE map and shows the callout under the chart only when there is a target
/// and at least two weigh-ins. The screen hands over the raw profile and the filtered
/// entries and nothing else, so the profile -> text chain is testable without pumping the
/// screen (B-pass: seven wiring mutants of the screen's old inline arguments survived).
class WeightProjectionLine extends StatelessWidget {
  const WeightProjectionLine({
    super.key,
    required this.profile,
    required this.entries,
    this.now,
  });

  /// `UserRepository.instance.getProfile()` (an empty map when there is none).
  final Map<String, dynamic> profile;

  /// The weigh-ins of the selected window, oldest first.
  final List<Map<String, dynamic>> entries;

  /// The clock of the date sentence (tests inject it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble() ?? 0;
    if (targetWeight <= 0 || entries.length < 2) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: WeightProjectionCallout(
        entries: entries,
        targetWeight: targetWeight,
        goal: profile['primary_goal'] as String? ?? '',
        now: now,
      ),
    );
  }
}

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
        return _onTargetRow(lastW, _asOf(last));
      case ProjectionCalloutKind.offTarget:
        return _offTargetRow(lastW, _asOf(last));
    }
  }

  // Maintain kinds only: " \u00B7 as of 3 Nov" when the last weigh-in is old, else ''.
  String _asOf(Map<String, dynamic> last) => maintainAsOfSuffix(
        lastDateKey: last['date'] as String? ?? '',
        now: now ?? nowWall(),
      );

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
  Widget _onTargetRow(double lastW, String asOf) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            WeightCalloutCopy.onTargetLine(
                  gapTenths: weightGapTenths(lastW, targetWeight),
                  target: targetWeight,
                ) +
                asOf,
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.ok),
          ),
        ),
      ],
    );
  }

  // Maintain, beyond the window: how far and on which side, no date.
  Widget _offTargetRow(double lastW, String asOf) {
    return Row(
      children: [
        Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            WeightCalloutCopy.offTargetLine(
                  gapTenths: weightGapTenths(lastW, targetWeight),
                  target: targetWeight,
                ) +
                asOf,
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.warn),
          ),
        ),
      ],
    );
  }
}
