---
bug_id: 524d12
date: 2026-05-24
batch: 2026-05-24 drift-fix batch (10 findings — 1 P0 + 3 P1 + 6 P2; 10th was orphan caught by T16 drift-detector re-run, closed in-batch per feedback_no_deferrals)
status: fixed
symptom: |
  The 2026-05-24 ECC adoption batch shipped the writer-reader-drift-detector
  subagent (B1). Its first run on workout + nutrition domains surfaced 9
  drift instances across the writer/reader contract — the same recurring
  bug class codified in feedback_writer_reader_field_drift_recurring.md
  (7+ instances since Test #6).

  Headline drifts:

  1. (P0) NutritionWriteService.computeLogKey assembled date strings
     hand-rolled (year/month/day extracted directly from DateTime) instead
     of via istDateStr. At IST midnight boundary, the writer produced a
     key keyed under the wrong IST date, disagreeing with every reader
     that subsequently called istDateStr to look up "today's nlog_*"
     rows. Symptom class: meals logged 23:30-23:59 IST appeared on the
     wrong day in the AI snapshot.

  2. (P1) AI snapshot PR projection reported SUM-across-sets reps as the
     "PR reps" value (a leftover from the Test #6 WorkoutWriteService
     rewrite where `reps_completed` was redefined as cumulative sum).
     Coach gave advice like "your PR is 80kg × 24 reps" when the user's
     actual PR set was 80kg × 8 reps × 3 sets.

  3. (P1) 6 readers across 5 train/ files read top-level
     `log['duration_seconds']` — a field that the canonical
     WorkoutWriteService writer NEVER emits at the top level. Duration
     lives per-set inside sets[]. All 6 readers fell through to null
     and rendered "0s" for timed exercises.

  4. (P2) workout_logs.exercise_name was the SESSION LABEL (e.g. "Push A"),
     not a per-exercise field. Schema column name was misleading every
     reader who guessed at semantics.

  Plus 5 smaller drifts (fallback-read dead code, fiber column gap,
  notes-stuffing, legacy-method removal, Gate 23 enforcement).
concept: writer_reader_drift_batch_2026_05_24
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method: computeLogKey, line: 733 }
  - { file: lib/core/services/nutrition_write_service.dart, method: logMeal_istDateStr_site, line: 88 }
  - { file: lib/core/services/nutrition_write_service.dart, method: logWater_istDateStr_site, line: 400 }
  - { file: lib/core/services/sync/sync_workout.dart, method: _syncWorkoutLogs_uses_workout_name, line: 133 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: prSetRepsForExlog, line: 1923 }
readers:
  - { file: test/contracts/nutrition_write_service_ist_anchored_test.dart, method: pins istDateStr usage, line: 1 }
  - { file: test/contracts/nlog_key_canonical_test.dart, method: pins gate, line: 1 }
  - { file: test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart, method: pins PR-set reps semantic, line: 1 }
  - { file: test/contracts/no_top_level_duration_seconds_reads_test.dart, method: pins absence of top-level reads, line: 1 }
  - { file: test/contracts/cloud_workout_logs_uses_workout_name_test.dart, method: pins workout_name projection, line: 1 }
hive_key_prefix: "nlog_ + exlog_"
hive_key_formula: "NutritionWriteService.computeLogKey (nlog_) + WorkoutWriteService.exlogKey (exlog_)"
sync_methods: [_syncNutritionLogs, _syncWorkoutLogs, _syncExerciseLogs, _syncWaterLogs]
restore_methods: [_restoreNutritionLogs, _restoreWorkoutLogs, _restoreExerciseLogs, _restoreWaterLogs]
cloud_table: nutrition_logs, nutrition_log_items, workout_logs, workout_log_exercises
cloud_columns: [workout_name, fiber, duration_seconds, food_name, serving_g]
contract_test_path: test/contracts/nlog_key_canonical_test.dart
ist_handling:
  - { file: lib/core/services/nutrition_write_service.dart, line: 88, fn: istDateStr }
  - { file: lib/core/services/nutrition_write_service.dart, line: 400, fn: istDateStr }
  - { file: lib/core/services/nutrition_write_service.dart, line: 738, fn: istDateStr }
provider_invalidations: []
telemetry_op_types:
  success: [drift_fix_batch_shipped]
  failure: [drift_fix_batch_regression]
cross_account_guard: "nutritionBox + workoutBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "hand-rolled date assembly in nutrition_write_service.dart (substring extract of year/month/day instead of istDateStr)", absent: true }
  - { pattern: "nlog_* key constructed outside WriteService canonical formula", absent_outside_canonical: true }
  - { pattern: "top-level log['duration_seconds'] read in train/ files", absent: true }
  - { pattern: "cloud workout_logs upsert uses exercise_name column", absent: true }
  - { pattern: "AI snapshot reports SUM-across-sets reps as PR reps", absent: true }
proposed_fix: |
  Single mega-commit covering 9 findings + migration 068 + Edge Function
  redeploy (weekly-report v20→v21) + new build Gate 23.

  T1: New permanent gate (scripts/check_nlog_key_canonical.dart) +
      contract test (test/contracts/nlog_key_canonical_test.dart).
      Mirrors Gate 17 (exlog_*). Allowlists 3 files.

  T2: 3 IST drift sites fixed in NutritionWriteService (logMeal line 88,
      logWater line 401, computeLogKey line 740 → all routed through
      istDateStr). Per feedback_ist_sweep_gap, in-batch sweep caught the
      3rd site (logWater) that the original drift scan missed.

  T3: Drop dead fallback reads (food_name, serving_g) in
      sync_nutrition.dart per-item projection — fields the writer never
      emitted but reader still tried to read first.

  T4: Per-item fiber projection — nutrition_log_items.fiber column added
      (migration 068) + sync projection writes it.

  T5: prSetRepsForExlog helper in ai_coach_repository.dart finds the set
      whose weight_kg matches the PR weight and reports THAT set's reps.
      Falls through to reps_completed for legacy rows without sets[].

  T6: 6 sites across 5 train/ files routed through
      WorkoutReadService.bestPerSetDuration. Top-level duration_seconds
      no longer read anywhere in train/.

  T7: Drop dead `notes: log['id']` stuffing in workout_logs sync (the
      Hive `id` was being written into the cloud `notes` text column for
      no reason — historical artifact).

  T8: Client sync projection renamed exercise_name → workout_name (the
      column was always a session label, never per-exercise).

  T9: Migration 068 LIVE — atomic rename + new fiber column. Founder
      gate approved per single-tester rationale. Preflight confirmed
      uniqueness was a standalone UNIQUE INDEX (not table constraint),
      so DROP INDEX/RENAME COLUMN/CREATE UNIQUE INDEX pattern.

  T10: weekly-report Edge Function (sole cloud reader of the renamed
       column) updated + redeployed to v21
       (ezbr_sha256 ec4c002321e78fdf4d2348f31f3ce2dec0dcd4c9eeb5f3072736ba952d8114df).

  T11: Delete legacy WorkoutRepository.logSetWithPrRescan (0 callers per
       preflight verification — last legitimate caller was tool_dispatcher
       logPR which audit 2026-05-16 routed through WorkoutWriteService.
       logExercise). Cascading dead code (3 helpers/class) also deleted.

  T12-T14: Gate 23 wired into /build-apk, SoT registry hive_field_name_nlog
           entry extended, CLAUDE.md §19 retro updated.
regression_test_planned:
  - test/contracts/nlog_key_canonical_test.dart
  - test/contracts/nutrition_write_service_ist_anchored_test.dart
  - test/contracts/nutrition_log_items_fiber_projection_test.dart
  - test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart
  - test/contracts/no_top_level_duration_seconds_reads_test.dart
  - test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart
  - test/contracts/cloud_workout_logs_uses_workout_name_test.dart
  - test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart
---

# Bug 524d12 — 2026-05-24 drift-fix batch

closes-batch: 2026-05-24-drift-fix

## Summary

The 2026-05-24 ECC adoption batch shipped 4 items, the headline being the
writer-reader-drift-detector subagent (B1). Its first run on workout +
nutrition domains surfaced 9 drift instances spanning the writer/reader
contract — same recurring class as the 7+ prior instances codified in
`feedback_writer_reader_field_drift_recurring.md`.

Per founder lock (Approach C: single mega-commit, no sub-batching) and
per `feedback_no_deferrals.md`, all 9 findings closed in this batch —
including 3 scope extensions caught during execution by in-batch sweeps
(matches `feedback_ist_sweep_gap.md`).

For this batch only, `feedback_gates_before_refactor.md` is waived —
Gate 23 (T1) ships alongside the refactors (T2-T11) rather than in an
earlier commit, because the entire batch lands as a single founder-locked
mega-commit. Future refactor batches still follow the gate-first ordering.

## Findings closed (10)

1. **nutrition-F1 [P0]** — `NutritionWriteService.computeLogKey` IST drift.
   Test: `test/contracts/nutrition_write_service_ist_anchored_test.dart`.
2. **nutrition-F2 [P1]** — Gate 23 (nlog_* canonical writer enforcement).
   Test: `test/contracts/nlog_key_canonical_test.dart`.
   Gate: `scripts/check_nlog_key_canonical.dart`.
3. **nutrition-F3 [P2]** — Drop dead fallback reads (food_name, serving_g).
   Test: `test/contracts/nutrition_write_to_read_contract_test.dart`.
4. **nutrition-F4 [P2]** — Per-item fiber column + projection.
   Test: `test/contracts/nutrition_log_items_fiber_projection_test.dart`.
5. **workout-F1 [P1]** — AI snapshot PR-set reps semantic.
   Test: `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart`.
6. **workout-F2 [P1]** — Drop top-level `duration_seconds` reads (6 sites).
   Test: `test/contracts/no_top_level_duration_seconds_reads_test.dart`.
7. **workout-F3 [P2]** — Drop dead `notes: log['id']` stuffing.
   Test: `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart`.
8. **workout-F4 [P2]** — Rename `workout_logs.exercise_name` → `workout_name`.
   Test: `test/contracts/cloud_workout_logs_uses_workout_name_test.dart`.
9. **workout-F5 [P2]** — Delete legacy `logSetWithPrRescan` (0 callers).
   Test: `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`.
10. **orphan-T16-train-provider-sets-completed [P2]** — `train_provider.dart`
    reads legacy `sets_completed` (4 sites) while WriteService emits canonical
    `set_number`. Caught by T16 drift-detector re-run as orphan; closed in-batch
    per `feedback_no_deferrals` via dual-name read pattern.
    Test: `test/contracts/train_provider_reads_set_number_dual_name_test.dart`.

## Migration 068

Version: `20260525010726`. Source: `supabase/migrations/068_drift_fix_batch.sql`.
Recorded in `backups/applied_migrations.json` as `068b_drift_fix_batch`.

Schema changes:

- `DROP INDEX uniq_workout_logs_user_date_name`
- `ALTER TABLE workout_logs RENAME COLUMN exercise_name TO workout_name`
- `CREATE UNIQUE INDEX uniq_workout_logs_user_date_workout_name (user_id, date, workout_name)`
- `ALTER TABLE nutrition_log_items ADD COLUMN fiber NUMERIC DEFAULT 0`

Atomic rename per founder choice (sole tester, controls all installs).
Preflight confirmed uniqueness was a standalone UNIQUE INDEX (not table
constraint), so DROP/RENAME/CREATE pattern was safe without an outage
window. Live verification SQL output to be captured in T16.

## Edge Function deploys

| Function | Version before | Version after | ezbr_sha256 | Reason |
|---|---|---|---|---|
| `weekly-report` | 20 | 21 | `ec4c002321e78fdf4d2348f31f3ce2dec0dcd4c9eeb5f3072736ba952d8114df` | SELECT against `workout_logs` updated to use `workout_name` (F4 cascade — sole affected cloud reader). |

## Regression tests added

Eight new contract tests pin the closed findings:

- `test/contracts/nlog_key_canonical_test.dart` (Gate 23 mirror)
- `test/contracts/nutrition_write_service_ist_anchored_test.dart` (P0 + 1 source-grep + 2 behavioral)
- `test/contracts/nutrition_log_items_fiber_projection_test.dart`
- `test/ai_coach/pr_snapshot_uses_pr_set_reps_test.dart` (4 cases)
- `test/contracts/no_top_level_duration_seconds_reads_test.dart`
- `test/contracts/cloud_workout_logs_no_notes_stuffing_test.dart`
- `test/contracts/cloud_workout_logs_uses_workout_name_test.dart`
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`

## Build gate added

**Gate 23 — nlog_* canonical writer enforcement.**

- Script: `scripts/check_nlog_key_canonical.dart`
- Contract test: `test/contracts/nlog_key_canonical_test.dart`
- Wiring: `.claude/commands/build-apk.md`

Mirrors Gate 17 (exlog_* canonical writer enforcement). Allowlists 3
files: `nutrition_write_service.dart` (canonical), `sync_service.dart`
(`_nlogKeyForRestore` mirror), `nlog_key_migrator.dart` (migration
mirror). Any new `nlog_*` key construction outside these files fails
the gate.

## Why this batch was a single mega-commit

Founder locked Approach C: ship all 9 findings + migration + EF redeploy
as one atomic commit on a single feature branch, then merge `--no-ff`
into `main` and build a single APK. Rationale:

- Sole tester (founder), so install-coherence concerns from staged
  rollouts don't apply.
- Migration 068 is atomic — splitting it across batches would force
  intermediate states where client and cloud disagree on the renamed
  column.
- Gate 23 (T1) is a regression-detection gate; per
  `feedback_gates_before_refactor.md` it would normally ship in an
  earlier commit, but for this batch the gate + the refactors land
  together because the entire batch is one commit. Future refactor
  batches still follow the gate-first ordering.

This is documented as a one-time waiver in the closure YAML's
`scope_extensions_during_execution` field.

## Scope extensions during execution

Per `feedback_no_deferrals.md` + `feedback_ist_sweep_gap.md`, 3 in-class
expansions were executed within the batch rather than deferred:

1. **nutrition-F1 sweep** caught a 3rd IST drift site at `logWater`
   (line 401) — original drift scan listed only 2 sites (lines 88 +
   740). Per feedback_ist_sweep_gap (first pass always misses 2-3
   sites), full file sweep is mandatory.
2. **workout-F2 sweep** expanded from 2 files to 5 files (6 sites):
   `workout_receipt_card.dart`, `edit_workout_log_sheet.dart`,
   `train_screen.dart`, `train_provider.dart`,
   `workout_repository.dart`. All routed through
   `WorkoutReadService.bestPerSetDuration`.
3. **workout-F5 cascading cleanup** deleted 3 confirmed-orphan helpers
   alongside the main method: `_invalidateExlogDateIndex`,
   `_recomputePrFlagsForExercise`, `_PrScanEntry`. Total net deletion:
   ~277 lines. `_exlogDateIndex` field + `_ensureExlogDateIndex` helper
   KEPT — preflight initially listed them as candidates but extension
   subagent verified `_ensureExlogDateIndex` is actively called from
   `getExerciseLogsForDate` legacy fallback path (line 521).

## Verification

### Verification — drift-detector re-run

Re-run executed on staged tree at branch `claude/frosty-bardeen-cce54b`
before mega-commit. Steps per `.claude/agents/writer-reader-drift-detector.md`.

#### Per-finding verification (9 cases)

| ID | Severity | Check | Result |
|---|---|---|---|
| nutrition-F1 | P0 | `grep '\.year\.toString' nutrition_write_service.dart` → 0 hits | PASS |
| nutrition-F2 | P1 | `scripts/check_nlog_key_canonical.dart` exits 0 + `nlog_key_canonical_test.dart` 1/1 passes | PASS |
| nutrition-F3 | P2 | `grep "item\['food_name'\]\|item\['serving_g'\]" sync_nutrition.dart` → 0 hits | PASS |
| nutrition-F4 | P2 | `grep "'fiber':" sync_nutrition.dart` → hit at line 185 (per-item projection) | PASS |
| workout-F1 | P1 | `grep prSetRepsForExlog ai_coach_repository.dart` → 2 hits (declaration 1923 + callsite 1970) | PASS |
| workout-F2 | P1 | `grep "log\['duration_seconds'\]" lib/features/train/` → 0 hits | PASS |
| workout-F3 | P2 | `grep "'notes': log" sync_workout.dart` → 0 hits | PASS |
| workout-F4 | P2 | `grep "'workout_name':" sync_workout.dart` → hit at line 133 (workout_logs upsert); `exercise_name` hits at 248/620/1058/1172/1604 confirmed in OTHER tables (workout_log_exercises, workout_log_sets, template_exercises, scheduled_workouts) where the column is legitimately per-exercise | PASS |
| workout-F5 | P2 | `grep logSetWithPrRescan workout_repository.dart` → 0 hits; cascading helpers `_invalidateExlogDateIndex` / `_recomputePrFlagsForExercise` / `_PrScanEntry` also → 0 hits | PASS |

All 9 closures verified PASS. 8 contract tests pass cleanly (18 cases
across the 8 files; full output captured in batch logs). Gate 17 +
Gate 23 both pass.

#### Workout domain re-scan

- **P0:** 0
- **P1:** 0
- **P2:** 0 (within scope of this batch; one pre-existing latent
  finding noted below as out-of-scope)

Verified writer↔reader pairs:
- `WorkoutWriteService.exlogKey` Gate 17 → PASS (UUID-v5 canonical)
- `set_number` writer at line 171 paired with reader normalization
  at lines 617-619 (legacy `sets_completed` → `set_number` promotion)
- `sets[]` per-set field including `duration_sec` paired with
  `WorkoutReadService.bestPerSetDuration` (6 sites)
- `prSetRepsForExlog` helper finds PR-matching set's reps (4 test
  cases pin: PR-set match / legacy fallback / empty sets / null)
- IST date keys: no hand-rolled assembly anywhere in `lib/`
  (`grep "DateTime.now().toIso8601String().substring(0, 10)"` → 0 hits)

Pre-existing latent finding caught by T16 re-run, **CLOSED IN-BATCH per
feedback_no_deferrals**:
4 readers in `train_provider.dart:1239,1241,1742,1757` read
`log['sets_completed']` as an int (count of sets) but the canonical
WriteService writes `set_number` instead. Fresh WriteService-emitted
logs would return null on these reads. The promotion at the WRITER
side (lines 617-619) only runs on `editLog`, NOT on `logExercise`,
so this was a latent bug that survives mainline `logExercise` writes.

**Closure:** all 4 sites updated to dual-name read with canonical-first
preference (`(log['set_number'] as int?) ?? (log['sets_completed'] as int?)`).
Same pattern as line 86 + ExerciseSet.fromMap (duration_sec/_seconds).
New finding entry `orphan-T16-train-provider-sets-completed` added to
closure YAML; new regression test
`test/contracts/train_provider_reads_set_number_dual_name_test.dart`
pins source-grep contract. Line 1757 reads from `workout_log` rows
whose writer (workout_repository.dart:411) still emits `sets_completed`
— dual-name applied for symmetry (canonical fallthrough is a no-op
there but keeps the reader contract uniform).

#### Nutrition domain re-scan

- **P0:** 0
- **P1:** 0
- **P2:** 0

Verified writer↔reader pairs:
- `NutritionWriteService.computeLogKey` uses `istDateStr` at line 738
- `logMeal` at line 88 and `logWater` at line 400 also use `istDateStr`
- Gate 23 enforces nlog_* canonical writer allowlist (3 files)
- `FoodItem.toMap` emits `name` field; sync projection at line 178
  reads `item['name']` — clean match (no `food_name` dead fallback)
- `fiber` per-item field round-trips: writer at FoodItem.toMap → Hive
  payload at NutritionWriteService line 105 (`items[].fiber`) → sync
  projection at sync_nutrition.dart:185 → cloud column `fiber` added
  by migration 068

#### New findings outside closure set

ZERO new drift findings introduced by this batch.

One pre-existing P2-class orphan reader drift in `train_provider.dart`
(`sets_completed` reads documented above) surfaced by T16 re-run.
Present in mainline since Test #6 WriteService rewrite. Per
`feedback_no_deferrals` and the in-batch pattern (T2 expanded 2→3
sites, T6 expanded 2→6 sites), **closed in this same mega-commit**
as the 10th finding (`orphan-T16-train-provider-sets-completed`).

#### Regression risk

NONE visible. All fix sites are surgical:
- IST routing through `istDateStr` (well-tested utility)
- New canonical reader helpers (`prSetRepsForExlog`, `bestPerSetDuration`)
  with full unit coverage
- Dropped dead fallback reads and dead methods (zero callers verified
  in preflight)
- Atomic cloud rename via migration 068 paired with single Edge
  Function redeploy (weekly-report v20→v21) — sole cloud reader
- 8 new contract tests pin behavior + Gate 23 prevents future
  regression

Live migration verification (preflight + post-apply SQL output
captured in batch logs):
- `workout_logs.workout_name` PRESENT
- `workout_logs.exercise_name` ABSENT
- `nutrition_log_items.fiber` PRESENT (DEFAULT 0)
- `uniq_workout_logs_user_date_workout_name` index PRESENT
- `uniq_workout_logs_user_date_name` index ABSENT
