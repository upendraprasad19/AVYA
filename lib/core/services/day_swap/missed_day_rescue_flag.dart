// lib/core/services/day_swap/missed_day_rescue_flag.dart
//
// OI-348 P3 (docs/plans/oi348-landing3d.md §3.1): the kill switch of the
// missed-day rescue. `configBox['disable_missed_day_rescue'] == true` turns
// the rescue off everywhere (engine rules, the freeze refund, the picker /
// drag pair rule, the footer); absent = ON. With it set, the engine's
// states, previews and swaps are what they were before the rescue existed.
// Two picker changes of the same landing are NOT behind it, on purpose: a
// locked SOURCE day says why instead of listing targets the swap would
// refuse (a pre-existing Home long-press bug), and a swap refreshes the
// streak-freeze chip.

import '../hive_service.dart';

const String kDisableMissedDayRescueKey = 'disable_missed_day_rescue';

/// True unless the kill switch is set. An unreadable config box reads as the
/// default (ON), like every other `disable_*` switch.
bool missedDayRescueEnabled() {
  try {
    return HiveService.instance.configBox.get(kDisableMissedDayRescueKey) !=
        true;
  } catch (_) {
    return true;
  }
}
