import 'package:flutter/material.dart';

import '../../../features/home/widgets/streak_badge.dart';
import 'ward_freeze_badge.dart';

/// WardStatusStrip — composes streak / freeze / optional rank chips into a
/// single horizontal Wrap.
///
/// Used as the [WardLetterhead] `trailing` slot on screens that surface
/// the user's standing (Daily, Train, Profile). Keeps the badge cluster
/// consistent across tabs without each screen rebuilding the row.
///
/// * [streakDays] — current streak length; passed through to
///   [StreakBadge]. Always rendered (StreakBadge handles its own
///   zero-state pulse logic).
/// * [freezesAvailable] — count for the inline ❄ chip. Hidden by
///   [WardFreezeBadge] when <= 0.
/// * [rankChip] — optional caller-supplied widget for a rank pill /
///   ribbon. The strip stays agnostic about its shape so different tabs
///   can opt in to different visualisations.
class WardStatusStrip extends StatelessWidget {
  const WardStatusStrip({
    super.key,
    required this.streakDays,
    this.freezesAvailable = 0,
    this.rankChip,
  });

  final int streakDays;
  final int freezesAvailable;
  final Widget? rankChip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StreakBadge(
          days: streakDays,
          freezesAvailable: freezesAvailable,
        ),
        WardFreezeBadge(count: freezesAvailable),
        ?rankChip,
      ],
    );
  }
}
