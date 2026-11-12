---
bug_id: 4f9b2e
date: 2026-11-11
batch: oi494-food-search-date
status: fixed
blast_radius: account
symptom: >-
  A meal logged from Nutrition food search (or saved by the coach's legacy food card, which calls the same
  FoodLogNotifier.logFood) at or after 18:30 IST was stored on the NEXT day's key, on every device including an IST
  phone. The same double shift made the coach snapshot's this_week_workouts window and "today" one day late from
  18:30 IST, and its 7-day step history started at tomorrow. OI-494 (filed 2026-11-10 as a non-IST-device bug).
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - file: lib/features/nutrition/providers/nutrition_provider.dart
    method: FoodLogNotifier.logFood (passed istNow() as date into logMeal; now nowWall())
    line: 1059
  - file: lib/core/services/nutrition_write_service.dart
    method: logMeal (dateStr = istDateStr(date), the nlog_ key and the row's date field)
    line: 93
  - file: lib/features/profile/services/profile_write_service.dart
    method: updateProfile / patchProfile updated_at stamp (was istNow().toIso8601String(); now nowWall().toUtc())
    line: 67
readers:
  - file: lib/core/services/nutrition_read_service.dart
    method_or_widget: today's meals and totals (read nlog_ rows by IST date string)
    line: 1
  - file: lib/features/ai_coach/services/ai_snapshot_builder.dart
    method_or_widget: _getThisWeekWorkouts (week window, todayStr) and _getStepHistory (step_<date> keys)
    line: 686
hive_key_prefix: nlog_
hive_key_formula: "nutritionBox['nlog_<istDateStr(date)>_<meal>_<hash>'] with date: istDateStr(date)"
sync_methods:
  - NutritionWriteService.logMeal -> syncNutritionData (unchanged)
restore_methods: []
cloud_table: nutrition_logs
cloud_columns: [date, created_at]
contract_test_path: test/contracts/ist_now_double_shift_behavioral_test.dart
ist_handling:
  - istNow() returns IST wall-clock COMPONENTS in a UTC-FLAGGED DateTime (instant + 5:30). istDateStr/istDateOf call toUtc() (a no-op on a UTC value) and add 5:30 again, so istDateStr(istNow()) is the IST date of instant + 11:00 on every host zone. Measured with dart on this VPS under TZ=Asia/Kolkata and TZ=UTC; both print 2026-11-12 for 22:30 IST on 2026-11-11.
  - Fix passes nowWall() (the seam-aware wall instant, DateTime.now() in release) and lets istDateStr apply the shift once; the week window takes the IST weekday from istDateOf(wall).
provider_invalidations:
  - none changed (logMeal's own set + weeklyNutritionProvider in logFood, unchanged)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "date: istNow\\(\\)", absent: true }
  - { pattern: "istDateStr\\(istNow\\(\\)", absent: true }
proposed_fix: >-
  FoodLogNotifier.logFood passes nowWall() to logMeal. AiSnapshotBuilder._getThisWeekWorkouts does its day arithmetic on
  the wall instant (IST weekday from istDateOf(wall)) and applies istDateStr once; _getStepHistory iterates from
  nowWall(). The istNow() doc comment, which said isUtc is false, now says what the value is and where it must not go.
  The last istNow() uses in lib/ were moved too (B-pass P3): ProfileWriteService's updated_at stamp and
  StatSnapshotService's photo taken_at wrote the IST clock reading with a Z suffix (5:30 ahead of the instant); both
  now write nowWall().toUtc().toIso8601String(). Neither has a reader today (updated_at is not in the profile push
  payload and the restore skip removes it from both sides; no caller passes photoUrls). A local variable named istNow
  in WorkoutRepository.completionRateOverWindow was renamed istWall, so lib/ holds no istNow token outside ist_date.dart.
regression_test_planned:
  - test/contracts/ist_now_double_shift_behavioral_test.dart
related_bugs:
  - fe579a  # ai_coach_repository istDateStr(istNow()) (docs/diagnoses/2026-05-06-ist-double-shift-ai-repo-fe579a.md)
  - 157d0c  # IST date-key cluster, 25 sites + check_local_date_key_drift gate (docs/diagnoses/2026-06-07-ist-date-key-cluster-157d0c.md)
recurrence: |
  Third instance of the istNow()-into-a-shifting-helper class (Test #11.1, fe579a, now 4f9b2e). fe579a's proposed_fix
  already said "never pass istNow() result to istDateStr"; the rule lived only in that doc and the debugging skill, and
  the istNow() doc comment said the opposite of the truth (isUtc false), so a reader of the helper had no warning.
  157d0c's gate (scripts/check_local_date_key_drift.dart) bans hand-built local date strings, not an istNow() value
  flowing into istDateStr or a WriteService date:, so it could not see this shape. Two existing tests encoded the bug:
  food_log_notifier_to_nutrition_log_items_test REQUIRED istNow() in logFood, and ai_snapshot_builder_only_test built
  its expected week with the same double shift (so it agreed with the code and went red only by time of day).
  Guard added this time: test D in the regression file fails on ANY istNow token in lib/ outside ist_date.dart (calls,
  tear-offs, prefixed calls; comments stripped by a string-aware scanner pinned by D0). It started as a per-file
  allowlist; the B-pass noted a count cannot tell a safe use from an unsafe one in the same file, so the remaining
  uses were moved and the allowlist is empty. The doc comment now carries the rule.
  Known-good fix applied: pass the wall instant, let the helper shift once.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "nutrition_provider.dart logFood, ai_snapshot_builder.dart _getThisWeekWorkouts + _getStepHistory, profile_write_service.dart updated_at, stat_snapshot_service.dart taken_at, workout_repository.dart local rename, ist_date.dart doc comment; 9 new tests green under TZ=Asia/Kolkata, UTC, Asia/Tokyo and America/Los_Angeles; 9 mutants red in both zones (table below); 2 bug-encoding tests repointed." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Behavioral tests write through FoodLogNotifier.logFood on real Hive and read the nlog_ row's key and date field back; the snapshot tests seed wlog_/exlog_/step_ rows and read them through buildAiContext/enrichContextForQuery." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Read-only query on dedsavbjuwgarrhphgnl 2026-11-11: 82 nutrition_logs rows, 1 has date > IST date of created_at, created 2026-09-26 18:09 UTC (23:39 IST), one tester account. Consistent with the bug. Not healed: the app is not live (testers only) and the device Hive copy is the source; see Data below." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function change. The server-side IST helper (_shared/ist_date.ts) is untouched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "The pushed row shape is unchanged; only the date value it carries is now right. No live trace was run; the device check is on the OI board after the next build." }
impact_analysis: >-
  Evening meals logged from food search or the coach food card now land on the day they were eaten, so today's
  calories/protein, the weekly chart and the coach's meals_today include them that evening instead of the next
  morning. The coach's this_week_workouts and step history no longer run a day ahead after 18:30 IST. Rows already
  written on the wrong day stay where they are (testers only, app not live).
---

# A food-search meal logged after 18:30 IST lands on tomorrow (4f9b2e, OI-494)

## Root cause
`istNow()` (`lib/core/utils/ist_date.dart`) is `_wallNow().toUtc().add(5:30)`: the result is UTC-flagged and holds
the IST wall-clock components. `istDateStr(t)` computes `t.toUtc().add(5:30)`; on a UTC-flagged value `toUtc()`
changes nothing, so the offset is added a second time. `FoodLogNotifier.logFood` passed `istNow()` as `date` into
`NutritionWriteService.logMeal`, which calls `istDateStr(date)` (line 93). Result: the IST date of "now + 11 h",
i.e. tomorrow from 18:30 IST, on any device. The OI was filed assuming the value is naive-local (as the doc comment
claimed), which would have limited the bug to non-IST devices; the probe showed it is not.

`AiSnapshotBuilder._getThisWeekWorkouts` and `_getStepHistory` fed `istNow()`-derived values into `istDateStr` the
same way.

## Fix
- `nutrition_provider.dart` logFood: `date: nowWall()`.
- `ai_snapshot_builder.dart`: week arithmetic on `nowWall()`, IST weekday from `istDateOf(wall).weekday`, each key
  through `istDateStr` once; step loop from `nowWall()`.
- `ist_date.dart`: `istNow()` doc comment corrected (UTC-flagged; never into a shifting helper or a WriteService date).
- Tests repointed: `food_log_notifier_to_nutrition_log_items_test.dart` (now requires `date: nowWall(),`, bans
  `date: istNow()`), `ai_snapshot_builder_only_test.dart` (planned_this_week pins the clock and spells the week).

## The other istNow() uses (moved in this batch after the B-pass)
- `profile_write_service.dart:67/95` `updated_at = istNow().toIso8601String()` wrote the IST clock reading with a `Z`
  suffix: a value claiming to be UTC that is 5:30 ahead. Nothing reads it today: the profile push builds an explicit
  field list without it (`sync_profile.dart`), `sync_profile.dart:838` says `updated_at` is server-set and never
  pushed, and the restore skip (`sync_profile.dart:893`) removes it from both sides. Now
  `nowWall().toUtc().toIso8601String()`, pinned by test E (clock pinned with a LOCAL DateTime, as in release, so a stamp
  that drops `.toUtc()` fails). The restore-skip comment that named `istNow()` was updated.
- `stat_snapshot_service.dart:317` photo `taken_at`: the same shape, inside a map over `photoUrls`; the only caller
  (`progress_comparison_screen.dart` `snapshotManual()`) passes none, so the branch never runs. Now the UTC instant,
  matching the progress-photo wire value (`progressPhotoTakenAtWire`).
- `workout_repository.dart:641` held a LOCAL variable named `istNow` (`nowWall()` + 5:30, read only for its
  components): renamed `istWall` so the guard can be zero-tolerance.

## Data
One cloud row (tester account, 2026-09-26 23:39 IST) sits on the next day. Not healed: pre-launch testers only
(CLAUDE.md §1), and the phone's Hive copy is the source the next push would compare against.

One edge of leaving a stray row in place: the `nlog_` key is date + meal slot + item hash (`computeLogKey`), so a
real log of the same food in the same slot on the stray row's day writes the same key and replaces it. That loses one
entry on a tester device; nothing double-counts or duplicates.

## Mutation evidence (rule 21)
Each mutant applied with sed, confirmed with `grep -c` (1 each), the file run under TZ=Asia/Kolkata and TZ=UTC,
then restored from a scratch copy and checked with `cmp`. Unmutated: 9/9 green in both zones (and under Asia/Tokyo
and America/Los_Angeles).

| id | file | edit | result (both zones) | red |
|---|---|---|---|---|
| M1 | nutrition_provider.dart | `date: nowWall(),` back to `date: istNow(),` | RED: A 18:31, A 23:59, D (18:29 control stays green) | 3 |
| M2 | ai_snapshot_builder.dart | `final wall = nowWall();` to `istNow()` | RED: B, D | 2 |
| M3 | ai_snapshot_builder.dart | step loop `nowWall()` back to `istNow()` | RED: C, D | 2 |
| M4 | ai_snapshot_builder.dart | IST weekday `istDateOf(wall).weekday` to `wall.weekday` | RED: B2 | 1 |
| MD1 | regression test, `_stripComments` | string literals not recognised (`if (false && ...)`), so a `//` in a string reads as a comment | RED: D0 | 1 |
| MD2 | regression test, `_istNowToken` | back to the call-only `\bistNow\(\)` | RED: D0 (tear-off). Before the local was renamed it also reddened D | 1 |
| M5 | profile_write_service.dart | updateProfile stamp back to `istNow().toIso8601String()` | RED: E, D | 2 |
| M6 | profile_write_service.dart | patchProfile stamp without `.toUtc()` | RED: E (green until E pinned a LOCAL clock: the seam's UTC value hid it) | 1 |
| M7 | stat_snapshot_service.dart | photo `taken_at` back to `istNow()` | RED: D (presence only: the branch is unreachable, so no behavioural test runs it; a `DateTime.now()` stamp there would stay green) | 1 |

M4 is the mirror-side mutant (a correct shift with the wrong weekday); B2 (03:00 IST Monday, still Sunday in UTC)
was added for it after M1-M3. B2 is green on main as well (the double shift lands on the same Monday at 03:00), so it
pins M4 only; A, B and C are the tests that fail on main. MD1 and MD2 prove the guard's own scanner after plan review #1 (P2): the first version
cut each line at its first `//`, so `'http://...'; istNow()` hid the call, and its regex missed a tear-off.
