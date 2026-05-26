# Drift Scan — workout domain — 2026-05-24

First run of `writer-reader-drift-detector` agent. Scope-capped to ~30
highest-impact field verifications across `exlog_*` / `wlog_*` /
`schedule_*` Hive shapes plus the three cloud projections
(`workout_logs`, `workout_log_exercises`, `workout_log_sets`).

## Summary
- P0 (active bug or contract violation): 0
- P1 (latent risk / partial coverage): 2
- P2 (convention drift): 3

## Writers covered

- `lib/core/services/workout_write_service.dart:166-179` — `exlog_*`
  Hive map (15 fields: `exercise_name`, `date`, `workout_log_id`,
  `sets[]` (w/ `weight_kg`, `reps`, `duration_sec`, `logged_at_ms`),
  `set_number`, `reps_completed` (SUM), `weight_kg` (MAX), `volume_kg`
  (SUM `w·r`), `logging_type`, `source`, `notes`, `updated_at_ms`,
  `is_pr`).
- `lib/core/services/workout_write_service.dart:355-378` — `wlog_*` Hive
  map + `schedule_*` Hive map (5/7 fields each).
- `lib/core/services/workout_write_service.dart:823-829` — canonical
  `exlogKey(date, name)` (UUID v5, Gate 17 enforced).
- `lib/core/services/sync/sync_workout.dart:126-135` — cloud
  `workout_logs` upsert (8 cols; `onConflict: user_id,date,exercise_name`).
- `lib/core/services/sync/sync_workout.dart:240-255` — cloud
  `workout_log_exercises` upsert (14 cols; `onConflict:
  workout_log_id,exercise_id,set_number`).
- `lib/core/services/sync/sync_workout.dart:288-305` — cloud
  `workout_log_sets` upsert (8 cols; same natural key).

## Readers covered

- 28 files across `lib/` grep-located. Spot-verified 7 highest-impact:
  - `lib/features/train/widgets/workout_receipt_card.dart:330-470`
  - `lib/features/train/screens/train_screen.dart:866-873, 1272-1297`
  - `lib/features/train/providers/train_provider.dart:74-102,
    1239-1250, 1739-1754`
  - `lib/core/services/workout_read_service.dart:65-112`
  - `lib/features/ai_coach/repositories/ai_coach_repository.dart:946,
    1249, 1582, 1925-1942`
  - `lib/features/train/widgets/edit_workout_log_sheet.dart:899-940`
  - `lib/features/train/repositories/workout_repository.dart:797-834,
    1361-1369`

Receipt + train_provider + train_screen + workout_read_service all use
the documented 4-source MAX policy (`set_number` ∨ `sets_completed` ∨
`sets[].length` ∨ `sets_detail[].length`) per Test #12.2 fix. This is
the canonical legacy-tolerant reader pattern on this codebase.

## Findings

### F1: PR snapshot emits SUM reps as "PR reps"

- **Severity:** P1
- **Writer:** `lib/core/services/workout_write_service.dart:172` —
  emits `reps_completed: int` with semantic SUM-across-sets.
- **Reader:**
  `lib/features/ai_coach/repositories/ai_coach_repository.dart:1939` —
  reads `reps_completed` and surfaces it to the AI snapshot as
  `'reps': N` under a PR record.
- **Drift type:** semantic
- **Real-world effect:** AI coach + weekly report may report "PR: 100kg
  × 50 reps" for a session where the user logged 5 sets of 10 reps at
  100kg. Should be the rep count of the PR-set specifically (single
  best set), not the SUM. Founder-visible only when an AI feature
  surfaces this number; receipt + Train screen render per-set chips
  via WardSetChips so the cumulative reps don't appear there.
- **Suggested fix:** Read first-set `reps` from `log['sets'][0]['reps']`
  (the canonical per-set semantic) or compute the max-weight set's reps
  specifically. Fall through to `reps_completed` only for legacy rows
  without `sets[]`.
- **Regression test to add:**
  `test/ai_coach/pr_snapshot_uses_per_set_reps_test.dart` — given an
  exlog with `sets:[{w:100,r:10}, {w:100,r:8}, …]` (5 sets), the PR
  snapshot must report `reps: 10` (or 8 — first OR PR-set), never
  `reps: 46` (SUM).

### F2: `exlog_*` reader reads top-level `duration_seconds` but writer never emits it

- **Severity:** P1
- **Writer:** `lib/core/services/workout_write_service.dart:166-179` —
  does NOT emit `duration_seconds` at top level of `exlog_*` rows.
  Per-set duration lives at `sets[].duration_sec` only.
- **Reader:** `lib/features/train/widgets/workout_receipt_card.dart:368`
  + `lib/features/train/screens/train_screen.dart` (multiple sites) —
  reads `log['duration_seconds']` at top level with `?? 0` fallback.
- **Drift type:** field name (top-level vs nested) — silent zero.
- **Real-world effect:** Dead-code-class read. Always 0 for
  WriteService-authored rows. Receipt + Train inline view bypass via
  `WardSetChips`/`bestPerSetDuration()` reads of nested
  `sets[].duration_sec` so timed exercises still render correctly.
  Latent risk: any future caller using `log['duration_seconds']`
  as a real signal will silently get 0.
- **Suggested fix:** Either (a) drop the top-level read and rely on
  `WorkoutReadService.bestPerSetDuration(log)` everywhere, OR
  (b) have the writer emit `duration_seconds` at top level (= sum of
  per-set durations) for parity with the cloud `workout_log_exercises`
  projection at sync_workout.dart:250 which DOES compute the aggregate.
- **Regression test to add:**
  `test/contracts/exlog_top_level_duration_emit_or_drop_test.dart` —
  enforce either (a) no top-level read for duration OR (b) writer emits it.

### F3: Cloud `workout_logs.notes` stuffs `log['id']` (always null for WriteService rows)

- **Severity:** P2
- **Writer:** `lib/core/services/sync/sync_workout.dart:133` — projects
  `'notes': log['id']` to cloud.
- **Reader:** No production reader detected. Cloud column is
  effectively write-only dead data.
- **Drift type:** semantic — `log['id']` is never set by
  `WorkoutWriteService`; the field is null for all post-Test-#6
  authored rows. The comment "store local ID for reference" is dead
  intent.
- **Suggested fix:** Drop the field from the projection. If a future
  reader needs the Hive key, the canonical mapping is
  `wlog_<date> ↔ user_id+date+exercise_name`.
- **Regression test to add:**
  `test/contracts/cloud_workout_logs_notes_dropped_test.dart` — assert
  the upsert payload no longer includes `notes`.

### F4: Cloud `workout_logs.exercise_name` is populated from Hive `workout_name`

- **Severity:** P2
- **Writer:** `lib/core/services/sync/sync_workout.dart:129` — emits
  `'exercise_name': wlogName` (where `wlogName = log['workout_name']`,
  e.g. "Push A").
- **Reader:** Weekly-report Edge Function reads this column as a
  session label. The naming is misleading — the column suggests an
  individual exercise but the value is a workout session name.
- **Drift type:** schema-naming convention drift.
- **Suggested fix:** Rename cloud column to `workout_name` via
  migration (low-risk additive — add new column, dual-write, switch
  readers, drop old column). Out of scope for a single batch; flag for
  schema-cleanup sprint.
- **Regression test to add:** None — schema rename, not a contract drift.

### F5: `workout_repository.logSetWithPrRescan` legacy writer still references `sets_detail`

- **Severity:** P2
- **Writer:** `lib/features/train/repositories/workout_repository.dart:1169`
  + `:1179-1205` — emits `sets_detail` + `sets_completed` (legacy
  field names).
- **Reader:** The canonical WriteService at `editLog`
  (`workout_write_service.dart:617-636`) DOES normalize these legacy
  names back to canonical `sets` + `set_number` on read-then-write.
  Receipt + Train reader's 4-source MAX policy also tolerates them.
- **Drift type:** convention — legacy writer path still in use.
- **Note from audit-2026-05-16 F6-2:** The AI coach `logPR` tool was
  routed off this legacy method onto `WorkoutWriteService.logExercise`.
  This repository method still has other callers (verify via grep) — if
  none remain, the method should be removed.
- **Suggested fix:** Grep all callers of `logSetWithPrRescan`; migrate
  any remaining to `WorkoutWriteService.logExercise`. Delete the
  method.
- **Regression test to add:**
  `test/contracts/no_legacy_log_set_with_pr_rescan_callers_test.dart` —
  source-grep fails if any file outside `workout_repository.dart`
  itself references the method (or, after removal, even within).

## Special signature checks

- ✅ **`exlog_*` keys produced by canonical only.** Sole emit site is
  `WorkoutWriteService.exlogKey()` at line 829. All other `'exlog_'`
  string usages in `lib/` are `.startsWith('exlog_')` reads or the
  migrator (which calls `exlogKey()` per Test #16.1 hardening).
- ✅ **`wlog_*` / `schedule_*` keys produced by canonical only.** Sole
  emit sites are `wlogKey()` (line 833) and `scheduleKey()` (line 837).
- ✅ **Duration field-name dual-read.** `ExerciseSet.fromMap`
  (write_result.dart) + sync per-set projection
  (sync_workout.dart:295) + receipt readers all accept BOTH
  `duration_sec` AND `duration_seconds`. No legacy-only readers found.
- ✅ **IST date keys.** Zero `toIso8601String().substring(0,10)` matches
  in `lib/`. All date-key assembly routed through `istDateStr()`.
- ✅ **UUID v5 deterministic IDs.** `exlogKey()` uses UUID v5 over
  `(namespace, lowercase+trim(name))` per H-16 fix.
- ⚠️ **`workout_log_id` Hive vs cloud disagree by design.** Hive emits
  `wlog_<date>` (line 169); cloud emits `_deterministicId('workout_<date>')`
  (UUID v5; sync_workout.dart:165). Functions correctly within each
  domain (Hive receipt scoping; cloud per-set FK). Receipt is the only
  reader that uses the field, and it reads from Hive only — no
  cross-domain join. Flagged for awareness, not action.

## SoT registry coverage

- Writers in scope: 4 services (`WorkoutWriteService` + 3 sync
  helpers `_syncWorkoutLogs` / `_syncExerciseLogs` /
  `_syncScheduledWorkouts`).
- Of those present in `docs/sot_registry.yaml`: 4 (all canonical
  workout-domain entries already registered per Test #11 +
  Test #15.4 SoT registry expansion).
- Absent from registry (recommend adding entry): 0.

## Overall

Baseline clean. The 5 findings (2 P1 + 3 P2) are all latent /
convention-level — no active user-visible bug. The 4-source MAX
reader pattern shipped in Test #12.2 + #12.4 + #15.3 is doing its
job across the canonical surfaces (receipt, Train screen,
train_provider, workout_read_service).

The P1 findings (F1 reps SUM semantic in AI snapshot, F2 unused
top-level `duration_seconds` read) are good candidates for the next
audit-cleanup batch but neither is a P0 ship-blocker.

Agent calibrated against known prior drift instances. Ready for
routine use on field renames and per-domain writer changes.
