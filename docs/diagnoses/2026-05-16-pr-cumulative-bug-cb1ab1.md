---
bug_id: cb1ab1
date: 2026-05-16
batch: audit-2026-05-16 reader-side / R2 (post-+27 install observation)
status: fixed
symptom: |
  Live screenshot 2026-05-16 (founder on APK +27 fresh install, signed in
  as upendraprasad19@gmail.com): home stats grid + PR snapshot showed
  cumulative SUM as "best per-set" value for non-weighted exercises —
  Push Up 100 reps, Hanging Leg Raise 85 reps, Jump Rope 5m 30s. The
  weighted exercise (Concentration Curl 15 kg) was correct because
  `weight_kg` is already MAX in the writer contract; only
  `reps_completed` / `duration_seconds` aggregate as SUM.
concept: exercise_personal_records
sot_registry_entry: exercise_personal_records
writers:
  - { file: lib/core/services/workout_write_service.dart, method: logExercise, line: 186 }
  - { file: lib/core/services/workout_write_service.dart, method: _rescanPrFor, line: 183 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method: loadAllExercisePRs, line: 595 }
  - { file: lib/features/home/providers/home_provider.dart, method: AllExercisePRsNotifier, line: 836 }
  - { file: lib/features/train/widgets/stats_grid.dart, method: StatsGridWidget, line: 181 }
  - { file: lib/features/home/widgets/pr_snapshot.dart, method: PRSnapshot, line: 23 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_${istDateStr(date)}_${uuidV5(lowercase+trim(name))}'"
sync_methods: [_syncExerciseLogs]
restore_methods: [_restoreExerciseLogs]
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, workout_log_id, set_number, reps, weight_kg, logging_type, is_pr, completed_at]
contract_test_path: test/contracts/load_all_exercise_prs_per_set_semantic_test.dart
ist_handling: []
provider_invalidations: [allExercisePRsProvider, currentPlanProvider, workoutStatsProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "user-scoped Hive (workoutBox) — guarded by HiveUserSession + authUserIdTokenProvider rebuild chain"
forbidden_patterns_checked:
  - { pattern: "log['best_single_set_reps']", absent: true }
  - { pattern: "log['best_single_set_duration']", absent: true }
  - { pattern: "raw['type'] != 'exercise_log'", absent: true }
proposed_fix: |
  Reader rewritten with 3 fixes:
  (1) Filter changed from `raw['type'] != 'exercise_log'` (modern
      WriteService doesn't stamp `type`) to key-prefix `exlog_*` —
      consistent with the audit Phase B fix to `_getPersonalRecords`.
  (2) Per-set MAX read from canonical `sets[]` array via fold across
      per-set entries. Top-level fields `reps_completed` (SUM) and
      `duration_seconds` (SUM) are no longer used as "best per-set"
      values.
  (3) Removed reads of fictional fields `best_single_set_reps` and
      `best_single_set_duration` (writer never produces them — they
      were a phantom reader contract).
  Single-set legacy rows without `sets[]` are recoverable via the
  top-level fallback gated by `set_number <= 1`. Multi-set legacy
  rows without `sets[]` are unrecoverable and now skipped rather
  than surfaced with cumulative as "best per-set".
regression_test_planned:
  - test/contracts/load_all_exercise_prs_per_set_semantic_test.dart
---
# Body

## Symptom

APK +27 install screenshot (founder, 2026-05-16):

```
PERSONAL RECORDS
- CONCENTRATION CURL  15 kg
- JUMP ROPE           5m 30s
- PUSH UP             100 reps
- HANGING LEG RAISE   85 reps
```

The user logged each of those exercises across multiple sets (e.g., Push
Up: 30 + 25 + 20 + 15 + 10 = 100 SUM). The PR card is supposed to show
the BEST single set, not the cumulative across all sets. Concentration
Curl is correct only because `weight_kg` is already MAX in the writer's
top-level summary — the bug-class affects `reps_completed` /
`duration_seconds` which are SUM.

## Root cause

`WorkoutRepository.loadAllExercisePRs` at
`lib/features/train/repositories/workout_repository.dart:595-661` had
THREE compounded defects:

1. **Filter mismatch.** Line 601 had
   `if (raw['type'] != 'exercise_log') continue;`. The canonical writer
   (`WorkoutWriteService.logExercise`) does NOT stamp `type` — it relies
   on the `exlog_*` Hive key prefix as the discriminator (per CLAUDE.md
   §15 "Hive field-name contract"). So this filter SKIPPED every modern
   writer output that wasn't legacy-typed.

2. **Phantom field reads.** Lines 620 and 627 read
   `log['best_single_set_reps']` and `log['best_single_set_duration']` —
   fields that the writer never produces. Both are always null.

3. **Cumulative fallback math.** Lines 621-623 and 628-630:
   `((reps_completed ?? 0) / (sets_completed ?? 1).clamp(1, 999))`.
   - `reps_completed` is SUM per the Test #6 writer contract.
   - `sets_completed` is null on modern rows (writer writes `set_number`).
   - `?? 1` evaluates first → divisor 1 → returns SUM unchanged as
     "best per-set".

The case-statement comment "Use per-set best reps (not cumulative)" was
a LIE. The math returned SUM. Trusting comments without verifying the
math was the methodology gap; codified in
`feedback_check_validators_before_drafting.md` (also relates to
`feedback_writer_reader_field_drift_recurring.md` — this is the 10th
instance of the writer/reader drift class).

## Fix

See `proposed_fix` in frontmatter. Three readers downstream
(`allExercisePRsProvider`, `StatsGridWidget`, `PRSnapshot`) all derive
from `loadAllExercisePRs` — fixing the canonical reader closes all
three displays.

## Regression test

`test/contracts/load_all_exercise_prs_per_set_semantic_test.dart` — 8
test cases covering: bodyweight_reps MAX, timed MAX, weight_reps MAX,
modern WriteService output INCLUDED (no `type` field), legacy
single-set recoverable, legacy multi-set SKIPPED, cardio cumulative-
by-design, forbidden-pattern source-grep.
