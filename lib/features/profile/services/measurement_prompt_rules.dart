import 'package:flutter/foundation.dart';

/// Whether (and which) body-measurements prompt to show (L2b Landing B, B3).
///
/// PURE: no Riverpod, no Hive. `none` shows nothing, `baseline` invites a first
/// set, `due` invites a fresh one.
enum MeasurementPrompt { none, baseline, due }

/// Days after the last entry at which a fresh set is due.
const int kMeasurementDueIntervalDays = 28;

/// Days a skipped baseline prompt stays quiet. A SECOND constant on purpose:
/// it is not the same meaning as [kMeasurementDueIntervalDays] even though both
/// are 28, and the two can diverge. (Swapping which branch reads which is
/// behaviourally equivalent while both are 28; the tests mutate each value
/// alone.)
const int kMeasurementBaselineSnoozeDays = 28;

/// Days a dismissal silences every nag surface of this landing.
const int kMeasurementDismissSnoozeDays = 7;

/// Days after onboarding before the first baseline prompt (D3 is a one-line
/// change of this constant).
const int kMeasurementBaselineFromTenureDays = 7;

final RegExp _kIstKeyShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Parses an IST day key (`YYYY-MM-DD`) strictly, or returns null.
///
/// The strict shape AND a numeric round-trip through `DateTime.utc(y, m, d)`:
/// `2026-13-45` and `2026-02-30` are absent, not normalised. NEVER a string
/// rebuilt with `padLeft` (`scripts/check_local_date_key_drift.dart` bans it).
/// Absent, non-`String`, unparsable and impossible values are all null.
///
/// The second copy of the reader's private `_isRealIstDateKey`
/// (`health_read_service.dart`); `measurement_prompt_state_behavioral_test.dart`
/// binds the two with a parity table. Day arithmetic everywhere in this file is
/// on UTC dates built by this function (no `DateTime(` and no `.toLocal()`),
/// pinned by a source test.
@visibleForTesting
DateTime? parseIstKeyStrict(Object? v) {
  if (v is! String || !_kIstKeyShape.hasMatch(v)) return null;
  final y = int.parse(v.substring(0, 4));
  final m = int.parse(v.substring(5, 7));
  final d = int.parse(v.substring(8, 10));
  final t = DateTime.utc(y, m, d);
  if (t.year != y || t.month != m || t.day != d) return null;
  return t;
}

/// The prompt for the given facts.
///
/// 1. `!flagOn`, `!historyKnown` (a failed history read must not look like
///    "never measured") or an unparsable [todayIst] -> `none`.
/// 2. Every date is parsed by [parseIstKeyStrict]; a FUTURE date (a wrong
///    device clock or the dev-panel clock stored it) is treated as absent. The
///    `onboarded` clause is behaviourally equivalent (a negative tenure fails
///    `tenure >= 7` anyway) and is kept for uniformity.
/// 3. [dismissedIst] less than [kMeasurementDismissSnoozeDays] ago -> `none`.
/// 4. Never measured ([lastEntryIst] absent): [baselineSkippedIst] less than
///    [kMeasurementBaselineSnoozeDays] ago -> `none`; otherwise `baseline` when
///    [onboardedIst] is present and the tenure is at least
///    [kMeasurementBaselineFromTenureDays], else `none`.
/// 5. Measured: `due` when at least [kMeasurementDueIntervalDays] days have
///    passed since the last entry, else `none` (no tenure floor).
MeasurementPrompt measurementPromptFor({
  required bool flagOn,
  required bool historyKnown,
  required String todayIst,
  String? onboardedIst,
  String? lastEntryIst,
  String? dismissedIst,
  String? baselineSkippedIst,
}) {
  final today = parseIstKeyStrict(todayIst);
  if (!flagOn || !historyKnown || today == null) return MeasurementPrompt.none;

  DateTime? pastOrToday(String? s) {
    final d = parseIstKeyStrict(s);
    return (d == null || d.isAfter(today)) ? null : d;
  }

  int daysSince(DateTime d) => today.difference(d).inDays;

  final lastEntry = pastOrToday(lastEntryIst);
  final dismissed = pastOrToday(dismissedIst);
  final skipped = pastOrToday(baselineSkippedIst);
  final onboarded = pastOrToday(onboardedIst);

  if (dismissed != null && daysSince(dismissed) < kMeasurementDismissSnoozeDays) {
    return MeasurementPrompt.none;
  }
  if (lastEntry == null) {
    if (skipped != null &&
        daysSince(skipped) < kMeasurementBaselineSnoozeDays) {
      return MeasurementPrompt.none;
    }
    if (onboarded != null &&
        daysSince(onboarded) >= kMeasurementBaselineFromTenureDays) {
      return MeasurementPrompt.baseline;
    }
    return MeasurementPrompt.none;
  }
  return daysSince(lastEntry) >= kMeasurementDueIntervalDays
      ? MeasurementPrompt.due
      : MeasurementPrompt.none;
}
