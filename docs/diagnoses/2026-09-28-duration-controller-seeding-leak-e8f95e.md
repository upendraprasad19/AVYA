---
bug_id: e8f95e
date: 2026-09-28
batch: reps-secs-invalidation-fixes
status: fixed
blast_radius: account
symptom: |
  Founder-reported (screenshot, 2026-09-28): logged "Single Leg Front Lever"
  (a custom bodyweight_reps exercise) as reps during an active workout
  scheduled from a template. The active workout screen correctly showed
  "8 reps" while logging, but after logging the persisted log rendered as
  seconds instead of reps (matching the recurring "reps shows as seconds"
  symptom family — see related_bugs below). Live Supabase confirmed
  workout_log_exercises rows for this exercise had reps_completed and
  duration_seconds carrying the same duplicated value.
concept: duration_controller_seeding_leak
sot_registry_entry: |
  exercise_logs_read_path — not a new registry concept. This is a
  writer-fidelity fix on the existing chain (docs/sot_registry.yaml:306;
  WorkoutWriteService.logExercise writes the sets[]/aggregate fields this
  concept owns). Distinct MECHANISM from the two prior diagnose-docs in
  this same symptom family (logged_sets_format_normalization / a4c7d1,
  active_workout_logging_type_resolution / 9b1e7a) — both of those are
  triggered by an exercise SWAP mid-workout; this bug requires no swap at
  all. The root cause is one layer further upstream: the UI's INPUT
  CONTROLLER itself was seeded with phantom data before any set was even
  logged. See lib/features/train/CLAUDE.md's new
  `duration_controller_seeding_leak` SoT-table row and
  lib/core/services/CLAUDE.md's extended `exercise_logs_read_path` row.
writers:
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "_initControllers — _durationControllers seed", line: 123 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout — builds ExerciseSet from SetInputValues", line: 1897 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise — aggregate computation (totalReps/maxWeight/volume)", line: 175 }
readers:
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: "EditLogExerciseRow.fromLog — reads persisted sets", line: 70 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: "WorkoutReceiptData.fromExerciseLogs — reads persisted sets + reps_completed", line: 310 }
hive_key_prefix: exlog_*
hive_key_formula: "exlog_${istDateStr(date)}_${hashExerciseName(name)}"
sync_methods:
  - "logExercise → unawaited(syncWorkoutData())"
restore_methods:
  - "sync/sync_workout.dart:_restoreExerciseLogs"
cloud_table: workout_log_exercises
cloud_columns:
  - sets (jsonb array)
  - reps_completed (int)
  - weight_kg (numeric)
  - volume_kg (numeric)
  - logging_type (string)
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "istDateStr(date) — Hive key + cloud date column, unaffected by this fix", line: 89 }
provider_invalidations:
  - activeWorkoutProvider
  - homeProviders (receipt display)
  - trainProviders (week summary)
telemetry_op_types:
  success:
    - workout_log_exercise_write
  failure:
    - workout_log_exercise_write_failed
cross_account_guard: "wrapUserScopedBox ensures per-user Hive isolation; no cross-account read possible — this bug is a same-account UI/aggregate correctness defect, not an isolation defect."
forbidden_patterns_checked:
  - { pattern: "direct Hive.box() call in exercise_card.dart or workout_write_service.dart", absent: true }
  - { pattern: "exercise_card.dart reading persisted logged data (writer-only, per repository pattern)", absent: true }
proposed_fix: |
  Two-part fix, both required — each closes a different half of the
  writer→reader chain:

  (1) **Stop the leak at its source** (exercise_card.dart:_initControllers,
  line 123). `_durationControllers` was seeded with `repsValue` — a
  copy-paste of the reps controller's seed line immediately above it.
  `LastPerformanceData` carries no duration field (only lastWeight/
  lastReps), so there was never a legitimate prefill source for duration.
  Fixed to seed empty, matching `_distanceControllers`' "no prefill data"
  shape immediately below it. `_captureSetValues` (line 218) parses BOTH
  `_repsControllers` and `_durationControllers` unconditionally regardless
  of which one `set_input_row.dart` actually renders for the exercise's
  `loggingType` — so any non-empty seed here silently leaks into
  `SetInputValues.durationSeconds` even for a pure reps-based exercise the
  user never saw a duration field for. This is exactly the leak the
  pre-existing `[durationCtl-leak]` debug diagnostic in
  train_provider.dart:1876-1892 (added in the APK Test #12.5 batch,
  commit d9b5462b) was placed to find — "WorkoutWriteService strips
  phantom durationSec post-resolve, but we want to know WHEN this happens
  at the source so we can find + fix the controller-leak path." This fix
  IS that fix.

  (2) **Make the aggregate agree with what's actually persisted**
  (workout_write_service.dart:logExercise). `totalReps`/`maxWeight`/
  `volume` — which become `entry['reps_completed']`/`weight_kg`/
  `volume_kg` — were computed from `mergedSets` (PRE-normalization, raw
  controller input) instead of `cleanedSets` (POST logging-type
  normalization + phantom-field stripping). For a custom exercise not in
  the seeded exerciseBox, `_resolveLoggingType`'s data-shape fallback
  reads `hasDur = sets.any(durationSec != null && >0)` — with the leak
  present, this wrongly resolved to `'timed'` (present-tense — fix (1)
  removes the leak's INPUT, but this fix (2) is independent hardening:
  ANY future/other path that lets a phantom durationSec reach
  `mergedSets` — including the a4c7d1/9b1e7a swap-scenario writers this
  same file already normalizes for — must never leave the TOP-LEVEL
  aggregate fields disagreeing with `sets[]`, which is the exact shape
  that produced the "reps_completed == duration_seconds" duplication
  Supabase showed). Fixed by moving the aggregate computation to AFTER
  `cleanedSets` is derived, reading from `cleanedSets` instead of
  `mergedSets`.

  Part (1) alone is what makes THIS specific report's exercise resolve to
  the correct `bodyweight_reps` type end-to-end (confirmed by tracing:
  empty duration controller → `int.tryParse('')` → null →
  `SetInputValues.durationSeconds = null` → `ExerciseSet.durationSec =
  null` → `hasDur = false` → data-shape fallback returns
  `bodyweight_reps`). Part (2) is defense-in-depth so the aggregate can
  never again diverge from `sets[]`, regardless of which upstream path a
  future phantom value takes.
contract_test_path: test/train/duration_controller_seeding_writer_to_reader_test.dart
regression_test_planned: |
  - test/train/duration_controller_seeding_writer_to_reader_test.dart
    (source-grep, PRESENCE only): pins the exact fixed line + the exact
    absence of the buggy copy-paste line in exercise_card.dart.
  - test/workout_write_service/aggregate_reflects_cleaned_sets_test.dart
    (BEHAVIORAL — the canonical behavioral_test_path for this concept):
    Test A reproduces the leaked-duration shape directly at the
    logExercise level and asserts reps_completed matches cleanedSets (0),
    not mergedSets (8) — this is the assertion that fails pre-fix.
    Test B is the golden path: no leaked duration → resolves to
    bodyweight_reps end-to-end, reps_completed=8.
  Both mutated and run (see touched_layers_checked tier-1 evidence below).
impact_analysis: |
  Scoped to: (1) any exercise whose active-workout duration input
  controller was never touched by the user (the overwhelming majority of
  reps/weight-based sets — a `timed`/`cardio` exercise's duration field IS
  legitimately used and is unaffected since its controller was always
  meant to hold a value); (2) any exercise not in the seeded exerciseBox
  library (custom exercises), since a library-known exercise's
  `_resolveLoggingType` never reaches the data-shape fallback that this
  leak corrupted.

  No impact on:
  - Exercises with weight > 0 (hasWeight short-circuits the 'timed'
    misresolution regardless of the leak).
  - Any exercise already in the seeded library (library lookup wins
    before data-shape inference runs).
  - The a4c7d1/9b1e7a swap-scenario fixes — this is an independent,
    additional root cause in the same symptom family, not a
    regression of either.
  - Existing persisted rows already affected — NOT healed by this batch.
    Filed as a follow-up (see Related below) since a healer needs its own
    writer/reader-chain analysis + regression test, out of scope for this
    batch's confirmed 4-bug + 1-enhancement approval.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "exercise_card.dart no longer seeds _durationControllers with repsValue; workout_write_service.dart computes aggregates from cleanedSets. Both mutation-proven: reverting the exercise_card.dart line reddened both duration_controller_seeding_writer_to_reader_test.dart assertions; reverting the workout_write_service.dart aggregate lines reddened aggregate_reflects_cleaned_sets_test.dart Test A (Expected 0, Actual 8) while Test B stayed green (correct — golden path mergedSets/cleanedSets agree for a correctly-resolved type)." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "exlog_* entries now store reps_completed/weight_kg/volume_kg consistent with sets[] for every newly-logged exercise. Verified via aggregate_reflects_cleaned_sets_test.dart reading the real Hive entry after logExercise." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "workout_log_exercises.sets is jsonb array; reps_completed/weight_kg/volume_kg are pre-existing numeric columns. No schema change — client now writes correct values into the same columns." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live query on workout_log_exercises for the founder's account (user_id d7a67a37-0b05-4f0a-b13c-388bff3cb59b) during investigation confirmed the reps_completed/duration_seconds duplication this fix addresses." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "Full chain traced by file:line (writers/readers above) rather than assumed; both ends of the chain now agree on logging_type resolution and the aggregate fields it produces." }
---

## Summary

Founder logged a custom bodyweight exercise ("Single Leg Front Lever") as
reps during an active workout. It rendered correctly as reps while
logging, but the persisted log showed seconds instead — the fourth
instance of this app's "reps renders as seconds" symptom family, and the
first NOT caused by an exercise swap.

## Root Cause

Two-part chain, named by writer + reader at every link before any fix was
proposed (per CLAUDE.md §4.1):

1. **`exercise_card.dart:_initControllers`** (line 111-124) — seeds four
   per-set `TextEditingController`s from `LastPerformanceData`. The
   weight and reps controllers correctly prefill from
   `lastPerf.lastWeight`/`lastPerf.lastReps`. The duration controller had
   no such field to prefill from — but was seeded with `repsValue` anyway
   (a copy-paste of the line above it), instead of being left empty like
   `_distanceControllers`, which has the identical "nothing to prefill"
   shape.

2. **`exercise_card.dart:_captureSetValues`** (line 218) — parses
   `_repsControllers[i].text` AND `_durationControllers[i].text`
   unconditionally into `SetInputValues`, regardless of which field the
   active `set_input_row.dart` actually renders for this exercise's
   `loggingType`. A phantom non-empty duration controller therefore always
   leaks into `SetInputValues.durationSeconds`, even for an exercise the
   user only ever saw a reps field for.

3. **`train_provider.dart:completeWorkout`** (line 1897) — builds
   `ExerciseSet(durationSec: vals.durationSeconds, ...)` directly from the
   leaked value. A pre-existing debug-only diagnostic two lines above
   (`[durationCtl-leak]`, added in the APK Test #12.5 batch specifically
   to find this exact path) fires here for any non-timed/cardio exercise
   with a positive leaked duration.

4. **`workout_write_service.dart:logExercise`** (`_resolveLoggingType`,
   line 159) — for a CUSTOM exercise (not in the seeded `exerciseBox`
   library — confirmed live: `user_custom_exercises.logging_type` =
   `"bodyweight_reps"` for this exercise, but that table is never
   consulted here), the resolver falls to data-shape inference:
   `hasDur = sets.any(durationSec != null && >0)`. With the leak present,
   this is wrongly `true`, and with `hasWeight = false` (a bodyweight
   exercise), the resolver returns `'timed'` — the mis-resolution that
   produces the visible bug.

5. **`workout_write_service.dart:logExercise`** (aggregate computation,
   pre-fix at what is now line ~144) — `totalReps`/`maxWeight`/`volume`
   were computed from `mergedSets` (BEFORE the type-based normalization
   that zeroes reps for a `'timed'`-resolved set), while `sets[]` itself
   is written from `cleanedSets` (AFTER normalization). This is a second,
   independent bug: even holding the mis-resolution fixed, the top-level
   `reps_completed` field could disagree with what `sets[]` actually
   stores for the same log entry — exactly the "reps_completed ==
   duration_seconds" duplication the live Supabase query showed.

## Fix

See `proposed_fix` in the frontmatter — two independent, additive fixes:
(1) stop seeding the duration controller with a phantom value; (2) always
compute the top-level aggregate from the post-normalization `cleanedSets`,
never the pre-normalization `mergedSets`.

## Related

Third confirmed instance of the "reps renders as seconds" recurring
symptom family (recurrence per CLAUDE.md §4.1.5):

- **9b1e7a** (2026-09-15) — swap mid-workout retained the OLD exercise's
  `logging_type` on the in-session `ActiveWorkoutData`.
- **a4c7d1** (2026-09-22) — swap mid-workout persisted the OLD format's
  `sets[]` values (pre-existing logged sets not re-normalized after a
  swap).
- **e8f95e** (this bug, 2026-09-28) — no swap involved at all; the input
  CONTROLLER itself was phantom-seeded before any set was logged, feeding
  a corrupting signal into the SAME `_resolveLoggingType`/
  `_normalizeSetsByLoggingType`/`_stripPhantomFields` machinery a4c7d1
  added.

All three are the same underlying class — writer/reader drift around
`logging_type` resolution and the fields that depend on it
(`feedback_writer_reader_field_drift_recurring.md`) — at three different
layers of the same pipeline (in-session exercise data → persisted set
values → aggregate fields). Appended to
`.claude/skills/debugging/SKILL.md` bug-class catalog per §5.1.

**Not fixed in this batch (filed, not silently dropped):** existing
Hive/cloud rows already affected by this bug retain their corrupted
`reps_completed`/`duration_seconds` values — this fix stops the leak for
NEW logs only. A boot-time healer (mirroring a4c7d1's Part 2 pattern)
would need its own writer/reader analysis to safely detect "this row's
aggregate disagrees with its own sets[]" without false-positiving on
legitimately-timed exercises. **Filed as OI-265** (`docs/audit/open_issues.md`,
minted via `sh scripts/mint_oi.sh` from this branch — corrected 2026-09-28
per B-pass finding 1, `docs/reviews/b6f1837bf486-review.md`: this line
previously claimed the follow-up was already "tracked via mint_oi.sh"
before the mint had actually been run, which the B-pass caught by finding
no matching entry on either board).

**Also not fixed (separately tracked, same reasoning):** `_resolveLoggingType`
never consults `HiveService.instance.customBox`/`user_custom_exercises` —
only the seeded library `exerciseBox`. For THIS bug, fix (1) alone makes
the data-shape fallback resolve correctly (hasDur becomes false once the
leak stops), so the customBox gap is not this bug's root cause and fixing
it is out of scope for the approved 4-bug batch. It remains a latent
issue for a genuinely different custom-exercise misclassification shape
(e.g. a custom `weighted_bodyweight` exercise, which data-shape inference
cannot distinguish from `weight_reps` since both have weight>0). **Filed
as OI-266** (same correction as OI-265 above — this line previously said
"filed as a follow-up OI" with no OI actually filed).
