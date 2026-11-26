// lib/core/copy/weight_callout_copy.dart
//
// The words of the Weekly Report weight card's Maintain lines (OI-518): how far the
// last weigh-in is from a hold-weight target. "Holding the line" is the Maintain
// card's own subtitle on the goal screen; "adjust your nutrition" is the existing
// callout's phrase. Weights are kg, the unit the card and its chart use.
//
// The gap arrives as INTEGER tenths of a kg (`target - last`, from
// `weightGapTenths` in `target_weight_check.dart`, the same expression the Maintain
// window rule uses) and is printed from integers only, never from a float: a gap
// the rule calls beyond 3.0 kg can never print "3.0", and one it calls inside can
// never print "3.1". This file imports nothing from `lib/features` (the caller
// computes the tenths), and a test pins both.
class WeightCalloutCopy {
  WeightCalloutCopy._();

  /// `|gapTenths|` as kg with one decimal ("34" -> "3.4", "30" -> "3.0").
  static String _gap(int gapTenths) {
    final a = gapTenths.abs();
    return '${a ~/ 10}.${a % 10}';
  }

  /// The target as the Maintain lines print it: whole when it is whole to the
  /// tenth ("75"), else one decimal ("74.8"). Precondition: `target > 0` and
  /// finite; anything else prints the empty string (the callout never reaches it:
  /// `projectionCalloutKind` returns `none` for a non-positive or non-finite
  /// target).
  static String targetLabel(double target) {
    if (!target.isFinite || target <= 0) return '';
    final t = (target * 10).round();
    return t % 10 == 0 ? '${t ~/ 10}' : '${t ~/ 10}.${t % 10}';
  }

  /// Inside the Maintain window (`|gapTenths| <= 30`): `Holding the line · 1.2 kg
  /// from your 75 kg target`, or `... · right on your 75 kg target` at 0.0 kg.
  /// Never called for a kind other than `onTarget`.
  static String onTargetLine({required int gapTenths, required double target}) {
    final t = targetLabel(target);
    if (gapTenths == 0) return 'Holding the line · right on your $t kg target';
    return 'Holding the line · ${_gap(gapTenths)} kg from your $t kg target';
  }

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The suffix the Maintain lines carry when the last weigh-in is old: `as of
  /// 3 Nov` (`as of 28 Dec 2026` when [lastDay] is in another year than
  /// [today]). Both arguments are IST CALENDAR dates built by the caller; only their
  /// year, month and day are read, and [today] supplies only the year. A [lastDay]
  /// after [today] is never passed (the caller returns no suffix for it).
  static String asOfSuffix({required DateTime lastDay, required DateTime today}) {
    final year = lastDay.year != today.year ? ' ${lastDay.year}' : '';
    return ' \u00B7 as of ${lastDay.day} ${_months[lastDay.month - 1]}$year';
  }

  /// Beyond the Maintain window (`|gapTenths| > 30`): `3.4 kg above your 75 kg
  /// target · adjust your nutrition to hold the line`. `gapTenths < 0` = the last
  /// weigh-in is above the target. Never called for a kind other than `offTarget`.
  static String offTargetLine({required int gapTenths, required double target}) {
    final side = gapTenths < 0 ? 'above' : 'below';
    return '${_gap(gapTenths)} kg $side your ${targetLabel(target)} kg target '
        '· adjust your nutrition to hold the line';
  }
}
