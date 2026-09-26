---
bug_id: e6a2f8
date: 2026-09-22
batch: oi-batching-strategy-e5e359 (Batch A)
status: fixed
blast_radius: account
symptom: |
  OI-228 Bug A (founder observed live, one of two bugs in the original
  filing — Bug B is unrelated and remains open): opening "Log Workout"
  from the AI coach chat on a day whose scheduled workout is already
  marked completed shows the SAME "NO WORKOUT SCHEDULED TODAY" empty
  state used for a genuinely empty day, instead of a distinct message
  telling the user they already logged today's session.
concept: log_workout_sheet_completed_day_state
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/ai_coach/widgets/log_workout_sheet.dart, method_or_widget: "_LogWorkoutSheetState._load", line: 1 }
readers:
  - { file: lib/features/ai_coach/widgets/log_workout_sheet.dart, method_or_widget: "_LogWorkoutSheetState._buildEmpty", line: 1 }
hive_key_prefix: "schedule_"
hive_key_formula: "schedule_<istDateStr(DateTime.now())>"
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/widgets/log_workout_sheet_completed_day_test.dart
ist_handling:
  - "_load() reads today's schedule via the existing istDateStr(DateTime.now()) key formula, unchanged by this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — reads only the current user's own Hive-scoped workoutBox, unchanged access pattern."
forbidden_patterns_checked:
  - "copy/UI string duplicated instead of branched — the two empty-state variants share the same widget tree shape, only the two Text children's content branches on _alreadyCompleted"
proposed_fix: |
  _load() already distinguished "nothing scheduled" from "something
  scheduled and not loggable" (status != null && status != 'planned' &&
  status != 'paused') but collapsed both terminal outcomes into the same
  _buildEmpty() copy. Added a new `_alreadyCompleted` bool field, set from
  `status == 'completed'` at the point _load() already reads the day's
  status, and branched _buildEmpty()'s two Text children (heading + body)
  on it: "WORKOUT ALREADY LOGGED" / "Today's workout is already logged.
  Head to Train to review it." vs. the pre-existing "NO WORKOUT SCHEDULED
  TODAY" copy, unchanged for the genuine-empty and other non-completed
  terminal statuses (e.g. 'skipped').
regression_test_planned:
  - test/widgets/log_workout_sheet_completed_day_test.dart
impact_analysis: |
  Single-widget, copy-only branch — no new Hive key, no new write path,
  no change to the loggable-form path (status == 'planned' or 'paused'
  unaffected, still falls through to the existing form). This widget had
  ZERO prior test coverage (grepped test/ — no existing
  log_workout_sheet_test.dart or equivalent before this batch), so the new
  file also newly pins the two PRE-EXISTING behaviors (generic empty state,
  loggable form for a planned day) alongside the one new behavior —
  without this batch, a future regression in either pre-existing path
  would have had no test to catch it.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter test test/widgets/log_workout_sheet_completed_day_test.dart: 4/4 green (1 font-priming + 3 behavioral). flutter analyze on log_workout_sheet.dart: clean." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Test seeds a real workoutBox schedule_<today> row via HiveService.instance.workoutBox.put(...) inside tester.runAsync(), matching the real _load() read path exactly (same key formula, same box)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "n/a — Hive-only read." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "n/a" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "n/a" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "n/a" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "n/a" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "n/a" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "n/a" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "n/a" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "n/a" }
  - { tier: 12, name: "Client → server contract", status: not_applicable, evidence: "Pure client-side widget copy branch, no server contract involved." }
mutation_proven:
  mutated: "git checkout -- lib/features/ai_coach/widgets/log_workout_sheet.dart (full revert to pre-fix HEAD), keeping the new test file."
  result: "flutter test test/widgets/log_workout_sheet_completed_day_test.dart: exactly 1 of 4 tests reddened — the completed-day case (expected 'WORKOUT ALREADY LOGGED' text, found the generic 'NO WORKOUT SCHEDULED TODAY' copy instead). The font-priming test, the genuine-empty-day test, and the planned-workout-still-loggable test all stayed green, confirming the fix is isolated to the completed-day branch and does not disturb the other two terminal states."
  confirmed_applied: "Diffed the reverted file against the fixed backup before and after restore; re-ran the full file green (4/4) after restoring from the backup copy at $TEMP/log_workout_sheet_FIXED.dart.bak."
---

## Summary

Founder-observed (OI-228, Bug A of two — Bug B is a separate, unrelated
issue in the same original filing and remains open, needing live
tracing): the "Log Workout" sheet's empty state does not distinguish
"nothing was ever scheduled today" from "today's workout was already
logged."

## Root cause

`_load()` already branched on the day's status enum (`planned` / `paused`
→ loggable form; anything else terminal → empty state) but `_buildEmpty()`
had only one copy variant, so a `completed` day and a genuinely-absent
schedule rendered identically.

## Fix

Added `_alreadyCompleted` (set from `status == 'completed'` where `_load`
already inspects status) and branched `_buildEmpty()`'s heading and body
text on it. The loggable-form path (planned/paused) is untouched.

## Verification

- `flutter test test/widgets/log_workout_sheet_completed_day_test.dart`:
  4/4 green — this is the widget's first-ever test file, so the suite also
  newly pins the two pre-existing behaviors (generic empty state; planned
  day still shows the loggable form) alongside the new completed-day copy.
- Mutation proof: full revert of the source fix (tests kept) reddens
  exactly the completed-day test; the other 3 stay green.
- Two testing pitfalls documented in root CLAUDE.md's common-pitfalls
  table were hit constructing this test and fixed per the documented
  remediation: real Hive I/O inside a `testWidgets` body must be wrapped in
  `tester.runAsync()` (fake-async zone hang), and Hive/path_provider mocks
  must be applied lazily with a font-priming first test with no mock active
  (GoogleFonts degrades loudly, not gracefully, once path_provider is
  mocked).

## Files changed

- Modified: `lib/features/ai_coach/widgets/log_workout_sheet.dart`
- Created: `test/widgets/log_workout_sheet_completed_day_test.dart`
- Modified: `docs/audit/open_issues.md` (OI-228 updated — Bug A closed,
  Bug B remains open, OI stays OPEN)
- Created: this diagnose-doc.
