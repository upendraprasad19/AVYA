---
bug_id: e7a2c4
date: 2026-06-12
batch: audit-2026-06-10
status: fixed
blast_radius: account
symptom: >
  Quarterly audit (L1/IST lens) finding. getWeeklyWorkoutCounts (workout_repository.dart)
  — the reader behind the reports "This Week" tile + the 4-week frequency chart —
  anchored its rolling window on raw `DateTime.now()` (device-local wall clock,
  WITH its time-of-day) and parsed each row's IST `date` key via
  `DateTime.tryParse` (local midnight), then bucketed by
  `now.difference(date).inDays`. Mixing a wall-clock `now` against a midnight
  `date` made the window a rolling 7x24h slice anchored on the current
  time-of-day, AND device-timezone-dependent — so the "This Week" count could be
  off by a day near midnight or for a device in a non-IST timezone. It also
  ignored the dev time-travel / year-sim clock seam (every other "what is today"
  read uses nowWall()/istTodayStr()).
concept: weekly_workout_count_ist_window
sot_registry_entry: hive_field_name_wlog
writers: >
  No writer changed — reader-side IST fix. The data read is the wlog_<date> row
  written by WorkoutWriteService.markCompleted (type:'workout_log' + IST date).
readers: >
  workout_repository.dart getWeeklyWorkoutCounts (the fixed reader) →
  reports_screen.dart "This Week" tile (line 376) + 4-week frequency chart (431).
hive_key_prefix: "wlog_"
hive_key_formula: "wlog_${istDateStr(date)} (the `date` field is an IST date-key)"
sync_methods: []
restore_methods: []
cloud_table: workout_logs
cloud_columns: "n/a — local read only; no cloud columns touched"
contract_test_path: test/contracts/weekly_workout_counts_ist_test.dart
ist_handling: >
  THE FIX. "today" is now the seam-aware IST date (istTodayStr() = istDateStr(nowWall())),
  and both today and each row's date are reduced to UTC-midnight (_dayUtc) so the
  days-ago diff is pure IST calendar-day arithmetic — no device-timezone drift, no
  time-of-day rolling, and the dev/year-sim clock seam is honored. A future-dated
  row (daysAgo < 0) is excluded.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "getWeeklyWorkoutCounts using raw DateTime.now() — replaced by seam-aware istTodayStr() so the window is IST-anchored + sim-aware."
  - "comparing a wall-clock now against a midnight-parsed date — both sides now reduced to UTC-midnight (whole-day calendar diff)."
proposed_fix: >
  Anchor on istTodayStr() (seam-aware IST today) and compare via a UTC-midnight
  helper _dayUtc(ymd) so the buckets are whole IST calendar days, timezone-neutral
  and seam-honoring. Exclude future-dated rows (daysAgo < 0).
regression_test_planned: >
  test/contracts/weekly_workout_counts_ist_test.dart — freezes the clock at a
  known instant (2026-06-11 18:30Z = 2026-06-12 00:00 IST), seeds wlog rows at
  today / 6d / 7d / 27d / 28d / future, asserts buckets [2,1,0,1]; second case
  moves the seam and asserts the same row re-buckets. Deterministic via the clock
  seam (pre-fix's raw DateTime.now() was untestable / machine-TZ-dependent).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "getWeeklyWorkoutCounts rewritten to istTodayStr() + _dayUtc whole-day diff; flutter analyze clean" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "weekly_workout_counts_ist_test 2/2 incl. seam-move re-bucket; reads wlog_ type:'workout_log' rows (f1c8e4)" }
impact_analysis: >
  Account blast radius, low severity (no data loss; reader-only). The "This Week"
  count + frequency chart could under/over-count by one day at the window
  boundary, and shift for a device whose timezone differs from IST — annoying but
  not corrupting. Sibling of f1c8e4 (same reader file, same "This Week" surface):
  f1c8e4 fixed WHICH rows are counted (the type filter), this fixes the IST WINDOW
  they are bucketed into. Both are needed for a correct "This Week" tile. The fix
  also brings getWeeklyWorkoutCounts under the dev/year-sim clock seam, closing a
  seam-coverage gap (the 2026-05-31 seam adoption missed this method).
---

# getWeeklyWorkoutCounts anchored on device-local now, not IST (e7a2c4)

## What happened
`getWeeklyWorkoutCounts` (the reader behind the reports "This Week" tile + 4-week
frequency chart) used raw `DateTime.now()` (device wall clock, with time-of-day)
and `DateTime.tryParse` (local midnight) and bucketed by `inDays`. That made the
window a rolling 7x24h slice anchored on the current time-of-day and dependent on
the device timezone, and ignored the clock seam.

## Root cause
The `date` keys are IST dates, but the reader compared them against a device-local
wall-clock `now` instead of the IST calendar date. Mixing a timed `now` with a
midnight `date` rolls the window by time-of-day.

## Fix
Anchor on `istTodayStr()` (seam-aware IST today); reduce both today and each row's
date to UTC-midnight (`_dayUtc`) for pure whole-IST-day arithmetic; exclude
future-dated rows.

## Verification
- `test/contracts/weekly_workout_counts_ist_test.dart` 2/2 (buckets + seam-move).
- `flutter analyze` clean.

## See also
- lib/features/train/repositories/workout_repository.dart (`getWeeklyWorkoutCounts`, `_dayUtc`)
- lib/core/utils/ist_date.dart (`istTodayStr`, `nowWall`, `setTestClockTo`)
- docs/diagnoses/2026-06-12-markcompleted-wlog-missing-type-f1c8e4.md (sibling — the type filter)
