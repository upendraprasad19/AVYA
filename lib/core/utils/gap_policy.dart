import '../services/hive_service.dart';

/// PRO long-gap policy (Piece B, plan `docs/plans/2026-10-18-pro-gap-policy-and-streak.md`).
///
/// Kill switch `disable_lapse_gap_policy` (configBox, absent = LIVE). `true`
/// restores the pre-policy behaviour everywhere this file is consulted: the next
/// phase starts at `max(today, plan_end + 1)`, the streak walk skips a rowless
/// day while the streak is 0, the completion rate ignores rowless days, freezes
/// are not zeroed after a gap and the coach gets no `plan_status`.
const String kDisableLapseGapPolicyKey = 'disable_lapse_gap_policy';

bool get lapseGapPolicyEnabled {
  try {
    return HiveService.instance.configBox.get(kDisableLapseGapPolicyKey) !=
        true;
  } catch (_) {
    // Box not open (pre-boot / test): the policy stays ON, like the other
    // `disable_*` switches.
    return true;
  }
}

/// Days a phase lasts (4 weeks), the window a returning user's next phase must
/// still cover for the gap start to apply.
const int kPhaseLengthDays = 28;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) {
  final day = _dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

/// PURE. The Monday the next phase starts on.
///
/// Policy ON and [gapStart]: the day after the old phase ended
/// (`planEnd + 1`, Monday-snapped) when that phase would still contain [today]
/// (its last day, `start + 27`, is today or later); every day that already
/// passed then shows as missed. A longer gap (the whole next phase would be in
/// the past) starts at the Monday of [today] instead: one phase, a blank gap.
///
/// Policy OFF or [gapStart] false (explicit graduation unlock = a fresh start):
/// the original rule, `max(today, planEnd + 1)` Monday-snapped.
DateTime phaseStartAfterGap({
  required DateTime planEnd,
  required DateTime today,
  bool gapStart = true,
  bool? policyEnabled,
}) {
  final on = policyEnabled ?? lapseGapPolicyEnabled;
  final candidate = _dateOnly(planEnd).add(const Duration(days: 1));
  final now = _dateOnly(today);
  if (!on || !gapStart) {
    return _mondayOf(candidate.isAfter(now) ? candidate : now);
  }
  final start = _mondayOf(candidate);
  final lastDay = start.add(const Duration(days: kPhaseLengthDays - 1));
  return lastDay.isBefore(now) ? _mondayOf(now) : start;
}

/// PURE. Whole days between the end of the old phase and [newStart] that have
/// no row (0 when the new phase starts right after, or earlier).
int blankGapDays({required DateTime planEnd, required DateTime newStart}) {
  final firstBlank = _dateOnly(planEnd).add(const Duration(days: 1));
  final gap = _dateOnly(newStart).difference(firstBlank).inDays;
  return gap > 0 ? gap : 0;
}

/// A blank gap of at least this many days holds at least 3 planned days (the
/// smallest plan is 3 days a week), which is the PRO freeze cap, so zeroing the
/// freezes equals spending one per missed day. A shorter gap (only the
/// graduation unlock can leave one) does not reset anything.
const int kMinBlankGapDaysForFreezeReset = 7;

/// PURE. [gapDays] to pass to `resetFreezesAfterGap`, or 0 for "do not reset"
/// (policy off, or the blank gap is too short to equal the cap).
int freezeResetGapDays(int blankGap, {bool? policyEnabled}) =>
    (policyEnabled ?? lapseGapPolicyEnabled) &&
            blankGap >= kMinBlankGapDaysForFreezeReset
        ? blankGap
        : 0;
