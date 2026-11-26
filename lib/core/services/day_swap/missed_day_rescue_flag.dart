// lib/core/services/day_swap/missed_day_rescue_flag.dart
//
// OI-348 P3 (docs/plans/oi348-landing3d.md §3.1): the kill switch of the
// missed-day rescue. `configBox['disable_missed_day_rescue'] == true` turns
// the rescue off everywhere (engine rules, the freeze refund, the picker /
// drag pair rule, the footer); absent = ON. With it set, every day-swap
// state, preview and swap is exactly what it was before the rescue existed.

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
