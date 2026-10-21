---
bug_id: c3e9a4
date: 2026-10-21
batch: l2-custom-repair (Batch 0b of d4b8e1; plan docs/plans/2026-10-21-l2-custom-repair.md)
status: fixed
blast_radius: platform
tier: full
symptom: |
  After Batch 0a (d4b8e1) stopped the generator auto-adding customs, plans
  generated BEFORE it still carry them. Cloud user_progress.plan_json.schedules,
  queried 2026-10-21 for every user with a custom exercise: only the founder
  (d7a67a37…) has his own custom names inside future planned rows — 46 entries
  over 16 planned days from 2026-10-21 (tuck planche, Barbell Planche Hollow
  Press, Cable Pull Down, L Sit, Elbow Lever, Single Leg Back Lever, Barbell
  Jump Squats), none carrying `swapped_via`. Today's row: 14 exercises = 8
  library + 6 customs. And a REPEAT phase advance would re-pin them into the
  next phase: _buildRepeatPins reads the finished phase's week-1/2 rows, and
  buildPinnedDays resolves a non-library pin name through the customs.
concept: l2_custom_autoappend_repair
sot_registry_entry: l2_custom_autoappend_repair
related_bugs: [d4b8e1, e7b2d4]
recurrence: |
  Same root cause as d4b8e1 (lever L2), not a new recurrence: this batch is the
  repair of the data L2 already wrote, split from 0a per §4.12.1 after two
  review rounds found material issues only in the repair half. e7b2d4 made
  customs eligible for L2 (it started storing primary_muscles). Class: an
  additive post-pass's output outlives the removal of the post-pass.
writers:
  - { file: lib/core/services/l2_custom_append_repair_migrator.dart, method: "L2CustomAppendRepairMigrator.runIfNeeded / _run (one-time per-user strip of planned/paused rows dated after today, via upsertScheduled)", line: 105 }
  - { file: lib/core/services/workout_write_service.dart, method: "upsertScheduled ifUnchangedFrom guard (rowChangedMessage) + completedDayRefusedMessage (named planGenerator completed-day refusal)", line: 670 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method: "buildPinnedDays → resolve() custom fallback → _buildCustomExercise, which now stamps customOrigin 'repeat_pin'", line: 719 }
  - { file: lib/shared/repositories/plan_engine/models.dart, method: "PlannedExercise.customOrigin (copyWith carries it; toMap writes custom_origin)", line: 153 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_buildRepeatPins → _withoutAutoAppendedCustoms (repeat pins from the finished phase's rows)", line: 752 }
  - { file: lib/features/auth/screens/restoring/heal_after_restore.dart, method_or_widget: "_runL2CustomRepair (both post-restore paths)", line: 86 }
  - { file: lib/core/services/auto_appended_custom.dart, method_or_widget: "isAutoAppendedCustom / isLibraryRow / stripRow (the one predicate)", line: 23 }
  - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: "hasExactNameWhere (every row of a name, not the first) + customNamesLower", line: 58 }
hive_key_prefix: "schedule_ (existing rows, rewritten through upsertScheduled) + latch l2_custom_repair_v1_done"
hive_key_formula: "unchanged: 'schedule_' + istDateStr(date); latch is the literal 'l2_custom_repair_v1_done' in workoutBox"
sync_methods: [pushWorkoutPlanForSyncDomain, syncWorkoutData]
restore_methods: [_restoreWorkoutPlan, mergeScheduleBundleIntoHive]
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: test/contracts/l2_custom_append_repair_migrator_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 76, fn: istTodayStr }
  - { file: lib/core/services/day_swap/day_swap_rules.dart, line: 43, fn: utcDate }
provider_invalidations: [currentPlanProvider]
telemetry_op_types:
  success: [l2_custom_strip]
  failure: [l2_custom_repair_withheld, l2_custom_repair_push_skipped, l2_custom_repair_migrator, l2_custom_repair_push, repeat_pins_custom_strip, bg_heal_l2_custom_repair]
cross_account_guard: "restoreSettledForCurrentUser (marker == live uid == Hive owner) gates the scan and is re-checked before every write, the plan push and the latch; the latch lives in the per-user workoutBox; every row read takes a fresh HiveService.instance.workoutBox"
forbidden_patterns_checked:
  - { pattern: "DateTime.parse / DateTime.tryParse in l2_custom_append_repair_migrator.dart (the write date comes from the key via DaySwapRules.utcDate)", absent: true }
  - { pattern: "a quoted day-row key prefix literal in auto_appended_custom.dart (Gate 19 confinement of exercise-level key reads)", absent: true }
  - { pattern: "a custom in a future planned row after the repair, unless coach-swapped or repeat-pinned (behavioural, l2_custom_append_repair_migrator_test)", absent: true }
  - { pattern: "ActiveWorkoutPersistence in l2_custom_append_repair_migrator.dart (its active_session key is written only after a logged set, so it cannot tell a started session; B-pass F1)", absent: true }
proposed_fix: |
  One predicate, auto_appended_custom.dart isAutoAppendedCustom: an exercise
  with no provenance stamp (`swapped_via` from a coach swap, `custom_origin`
  from a repeat pin) whose trimmed lower-cased name is one of the user's
  customs (ExerciseRepository.customNamesLower) and that the library does not
  also hold. "The library holds it" = some exerciseBox row of that name is not
  a community-approved custom (isLibraryRow, via
  ExerciseRepository.hasExactNameWhere, which checks EVERY row of the name: a
  community row can share a bundled row's name). stripRow returns a NEW map
  (rows read back from Hive share their list with Hive's cache).
  (1) Repeat pins: _buildRepeatPins strips the finished phase's week-1/2 rows
  before repeatPinsFrom; fails OPEN (records repeat_pins_custom_strip) so a
  strip failure never aborts a phase advance. buildPinnedDays stamps every
  custom it rebuilds with customOrigin 'repeat_pin' (PlannedExercise →
  custom_origin in the row), so a pinned custom survives the next strip.
  (2) One-time repair: L2CustomAppendRepairMigrator, run from both post-restore
  paths after PlanIntegrityReconciler. Gates in order: kill switch, latch,
  customs non-empty, restore settled for this account. Rows dated AFTER today
  with type workout, status planned or paused, and no template, re-read per
  row, are rewritten as full copies through upsertScheduled(source:
  planGenerator, ifUnchangedFrom: <the row read>): refused if another writer
  replaced the row after the read (rowChangedMessage, no latch). The date
  comes from the KEY via DaySwapRules.utcDate. A row carrying arranged_at_ms
  is re-stamped with the write time. Never empties a row. TODAY's row is never
  rewritten (a started session leaves no stored marker until its first logged
  set); a pass that would have changed it does not latch. The plan push is
  issued after every completed scan (a previous pass may have stripped rows
  and stopped; _syncWorkoutPlan skips an unchanged plan), withheld if a
  planned workout day from today on is exercise-less. Latch only when the push
  was issued, no write failed or met a changed row, the pass was not stopped
  and today's row needed nothing.
  §4.6: kill switch `disable_l2_custom_strip` (SyncFlags.l2CustomStripEnabled,
  configBox, absent = ON) skips both, byte-identical to the build before. The
  custom_origin stamp is not behind it: it is additive provenance on new pins
  only, read by nothing but the predicate.
regression_test_planned:
  - test/contracts/auto_appended_custom_test.dart
  - test/contracts/l2_custom_append_repair_migrator_test.dart
  - test/contracts/l2_repeat_pins_strip_test.dart
  - test/contracts/l2_custom_repair_wired_test.dart
  - test/workout_write_service/upsert_scheduled_test.dart
  - test/contracts/repeat_phase_pinned_selection_behavioral_test.dart
impact_analysis: |
  The founder's planned days after the day the build first runs return to the
  8 library exercises the volume filter chose (that day's own row keeps them
  until it is past); his past and completed days are untouched; a coach swap
  or a repeat-pinned custom stays. Users without customs: the migrator returns before any
  scan (no latch) and the repeat-pin read is unchanged. Users with customs but
  no polluted rows: one scan, nothing written, latched. A later repeat advance
  never re-pins a custom L2 added.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ + the touched tests: 0 errors, 0 warnings; new tests 4 files + 2 extended (upsert_scheduled, repeat_phase_pinned_selection), all green, plus 144 neighbour tests and the exercise-seam gate (inventory unchanged, 36 sites); 5 + 15 mutations recorded below" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "migrator test on real Hive with the founder's live row as fixture: 6 customs stripped under the same key, a present arranged_at_ms re-stamped with the write time (an absent one stays absent), latch in the per-user workoutBox; a concurrent writer holding the date lock wins over the stale strip" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "2026-10-21 query over every user with a custom: only the founder has custom names in future plan_json rows (46 entries, 16 days, 0 with swapped_via); none of the 7 names collides with the 292-row bundled library; template-assigned rows of those 7 users end 2026-10-09, before the polluted plan's start, so no displaced_ backup holds a polluted row" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "client-only; no server reads plan_json exercise names to generate plans" }
  - { tier: 12, name: "Client to server contract", status: verified, evidence: "the stripped rows reach plan_json through the existing pushWorkoutPlanForSyncDomain (no payload shape change); restore merge keeps a local row that has exercises (mergeScheduleEntry), so a not-yet-pushed cloud row cannot put the customs back on this device" }
mutation_proven:
  mutated: "five, each applied by an exact-match replace (count 1) and restored byte-identical (cmp): (P) drop the swapped_via clause in isAutoAppendedCustom; (a) replace the restore-settled gate with if (false); (b) latch despite a failed write (drop failed == 0); (c) latch on empty customs; (R) bypass _withoutAutoAppendedCustoms in _buildRepeatPins"
  result: "(P) 4 RED: predicate 'a coach swap to a custom stays', stripRow order test, migrator 'a coach swap to a custom stays', repeat pins (2). (a) 2 RED: both withheld tests. (b) 1 RED: 'a failed write does not latch'. (c) 1 RED: 'no customs: nothing stripped and no latch'. (R) 2 RED: repeat pins (1) and (3)."
  confirmed_applied: "grep -c of the mutated line after each apply (swapped_via 1 → 0; 'if (false) {' 0 → 1; 'failed == 0' 1 → 0; 'if (customs.isEmpty) {' 0 → 1; '_withoutAutoAppendedCustoms(getWeek' 1 → 0) and cmp of each restored file"
  bpass_fix_mutations: "fifteen more after the B-pass fixes, by a script that replaced exactly one occurrence, re-counted it, ran the named test files, restored by copy (never git checkout) and checked sha1sum of all six files against a pre-cycle record (all OK). Each turned only its target RED, none a compile error: m1 drop the today skip → 'today's row is never rewritten'; m2 planned-only statuses → 'a paused future day is stripped'; m3 no re-stamp → the re-stamp test; m4 drop ifUnchangedFrom: raw → the date-lock concurrency test; m5 a changed row counted as benign → 2 RED (changed-row + concurrency); m6 push only when rows were written (the old rule) → 'stripped every row but stopped before the push'; m7 latch ignores a withheld push → 'push withheld … no latch'; m8 first-row getByExactName lookup in the migrator → 'a community row sharing a bundled name'; m9 isLibraryRow always true → 3 RED (predicate, migrator community, repeat pins 2c); m10 predicate ignores custom_origin → 2 RED (predicate, repeat pins 2b); m11 no 'repeat_pin' stamp, m12 copyWith drops customOrigin, m13 toMap drops custom_origin → each pinned-selection (7); m14 first-row lookup in the read service → repeat pins (2c); m15 upsertScheduled ignores ifUnchangedFrom → 2 RED (upsert test, concurrency test)"
---

## Summary

Removes the custom exercises the removed generator lever L2 had already put
into plans: once from future planned rows, and from every repeat phase's pins.

## Root cause

d4b8e1: lever L2 appended every muscle-matching custom to every generated day.
0a removed the lever; the rows it had written stayed, and the repeat-pin path
reads exactly those rows.

## Fix

See `proposed_fix`. Plan with its five review rounds:
`docs/plans/2026-10-21-l2-custom-repair.md`.

## Presence only (said plainly)

`l2_custom_repair_wired_test.dart` is a source-grep of the two call sites and
their order. The east-of-IST date trap is covered by `writeDateForSuffix`'s
behavioural test (UTC date, `istDateStr` and `DaySwapRules.format` round trip,
invalid dates rejected), not by running on an east-of-IST clock.

## B-pass (2026-10-21) and what changed

The B-pass on the first draft (0 P0, 0 P1, 2 P2, 7 P3) is fixed in this batch:
F1 today's row is never rewritten (the `active_session` key it relied on is
written only after a logged set); F2 re-stamp `arranged_at_ms` and this
section corrected; F3 push after every completed scan, latch only if issued;
F4 tests that discriminate (no write attempted for completed/rest/travel rows,
a re-scan with the latch cleared attempts none); F5 paused rows stripped; F6a
the `custom_origin` stamp on repeat pins; F6b community rows are not library;
F7 `ifUnchangedFrom`; F8 the writer cite; F9 the plan-review record. One more,
found while fixing F6b (its mirror): `getByExactName` returns the FIRST row of
a name, so a community row sorting before a bundled row of the same name
would have hidden the bundled one; `hasExactNameWhere` checks every row.

## Known limits

- The re-stamp trade-off: the stripped week now carries the newest
  `arranged_at_ms`, so on another device it wins the restore merge over an
  older arrangement. The pass runs right after this device's own restore, so
  it already holds every swap pushed before it; only a swap made elsewhere in
  the seconds between that restore and the write is overruled.
- A device still on an old build that swaps days AFTER the repair writes a
  newer stamp, and its polluted week wins on the repaired (latched) device
  until the old device updates: its own repair then re-stamps newer, and the
  stripped week wins back.
- Travel rows are skipped: travel mode marks rows `travel` for at most 7 days
  and never sets them back to `planned`, so they become past unchanged.
- A custom DELETED after L2 added it is not in `customNamesLower` and stays in
  the row (the user can swap it out).
- `restore_custom_exercises` is not streak-critical, so a partially restored
  custom list can latch a partial strip.
- A custom pinned by a repeat advance on a build BEFORE this one carries no
  `custom_origin` and would be stripped. The 2026-10-21 data check found none.
- An issued plan push that then fails is not awaited before the latch; it is
  re-sent by the next plan push (weeklyFullSync), because the plan skip index
  confirms a fingerprint only after a successful upsert.
- `displaced_<date>` backups are not written: they are local-only copies made
  when a template replaces a day, and no polluted day was ever replaced (see
  tier 4 evidence).
- The plan blob `workoutBox['current_plan']` keeps the customs; nothing
  rebuilds rows from it (its readers read metadata only).
