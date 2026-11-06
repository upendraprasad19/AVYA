---
bug_id: 9b1e7a
date: 2026-09-15
batch: Internal-testing observation batch, session 2 (Obs 6)
status: fixed
blast_radius: feature
symptom: |
  Founder-reported: swapped a timed exercise for a weight/reps exercise mid
  active-workout. The weight/reps exercise kept showing the timed UI (sets +
  duration + rest timer) instead of weight/reps inputs. Had to remove and
  re-add the exercise for the UI to become correct.
concept: active_workout_logging_type_resolution
sot_registry_entry: |
  Not applicable — this is a writer-fidelity fix on an existing
  writer/resolver chain (SwapExerciseData -> swap_sheets.dart onSelect ->
  ActiveWorkoutNotifier.swapExercise -> LoggingTypeResolver), not a new
  concept. `logging_type` for swap is already documented in
  lib/features/train/CLAUDE.md's "Logging types" table.
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "SwapExerciseData class definition", line: 264 }
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: "library-exercise SwapExerciseData(...) construction", line: 324 }
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: "custom-exercise SwapExerciseData(...) construction", line: 347 }
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, method_or_widget: "_showSwapSheet onSelect (ExerciseData construction)", line: 65 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutNotifier.swapExercise -> LoggingTypeResolver.resolve", line: 1432 }
  - { file: lib/features/train/screens/active_workout/exercise_card.dart, method_or_widget: "switch (widget.exercise.loggingType) — logging-type-driven UI branches", line: 262 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/swap_exercise_logging_type_behavioral_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure in-session provider state, no Hive/cloud read across accounts."
forbidden_patterns_checked:
  - { pattern: "swap_sheets.dart's _showSwapSheet onSelect building the replacement ExerciseData with loggingType: currentExercise.loggingType (the OUTGOING exercise)", absent: true }
proposed_fix: |
  Three-part fix, one per link in the chain: (1) SwapExerciseData gains a
  loggingType field; (2) both real SwapExerciseData construction sites in
  exercise_swap_sheet.dart thread the picker row's own logging_type through;
  (3) _showSwapSheet's onSelect reads swapEx.loggingType ?? '' (never
  currentExercise.loggingType) for the replacement ExerciseData's
  loggingType, so LoggingTypeResolver.resolve() either trusts the correct
  direct value or falls through to its own by-name library lookup — never
  silently inherits the outgoing exercise's type.
regression_test_planned:
  - test/contracts/swap_exercise_logging_type_behavioral_test.dart
impact_analysis: |
  Scoped to the SWAP path only. The "+ ADD EXERCISE" path
  (_showExercisePickerSheet -> addExercise) was already correct — it reads
  the newly-picked exercise's own logging_type directly and was verified
  live (Obs 5 investigation, same batch) to append cleanly with no field
  confusion. _openCreateAndAutoSwap (the "+ ADD EXERCISE" button INSIDE the
  swap sheet, sentinel __ADD_MODE__) was also already correct — it reads
  loggingType from the newly-created custom exercise's own form data, never
  from `original` (the exercise being replaced). Only _showSwapSheet's direct
  pick-an-existing-exercise path had the bug. No Hive/cloud field changed —
  ExerciseData.loggingType is still resolved to a valid non-empty string
  before being persisted; only WHICH string is now correct.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "SwapExerciseData.loggingType + both exercise_swap_sheet.dart construction sites + swap_sheets.dart onSelect fixed; flutter analyze clean." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "In-session ActiveWorkoutData only — nothing persisted to Hive until the workout is logged/completed, at which point WorkoutWriteService reads the now-CORRECT resolved loggingType same as before." }
---

## Summary

Founder-reported (internal-testing batch, session 2, 2026-09-15, Obs 6):
swapping a timed exercise for a weight/reps exercise mid active-workout kept
showing the timed UI (sets + duration + rest timer) for the new exercise,
until it was removed and re-added.

## Root Cause

Three-part chain, confirmed by naming writer + reader at every link before
proposing a fix (per CLAUDE.md §4.1):

1. **`SwapExerciseData`** (`lib/features/train/providers/train_provider.dart:264`
   pre-fix) — the picker's return type for `_showSwapSheet` — had fields
   `name`, `detail`, `emoji`, `id` but **no `logging_type` field at all**. The
   picker rows in `exercise_swap_sheet.dart` (both the library list and the
   custom-exercise list) DO have a `logging_type` in their source `Map` (the
   custom-exercise row even displays it: `'Custom · ${ex['category']} ·
   ${ex['logging_type'] ?? 'weight_reps'}'`), but neither of the two
   `SwapExerciseData(...)` construction sites (lines 324, 347) carried it
   forward.

2. **`_showSwapSheet`'s `onSelect`** (`lib/features/train/screens/active_workout/swap_sheets.dart:65`
   pre-fix) — with no `swapEx.loggingType` to read, it built the replacement
   `ExerciseData` with `loggingType: currentExercise.loggingType` — the
   **OUTGOING** exercise's type, not the incoming one's.

3. **`LoggingTypeResolver.resolve()`** (`lib/core/services/template_service.dart:378`)
   trusts a non-null, non-empty `logging_type` **verbatim**, without
   validating it against the exercise's name:
   ```dart
   final direct = exercise['logging_type'] as String?;
   if (direct != null && direct.isNotEmpty) return direct;
   ```
   Since step 2 always supplied a non-empty string (the outgoing exercise's
   real type), the resolver never reached its own by-name library fallback —
   which is exactly the mechanism that WOULD have corrected this, had the
   input been empty/null instead of confidently wrong.

The "+ ADD EXERCISE" button on the active workout screen
(`_showExercisePickerSheet` -> `addExercise`) was NOT affected — it reads the
picked exercise's own `logging_type` directly from the picker's library data
and was live-verified during the Obs 5 investigation this same session to
append correctly. `_openCreateAndAutoSwap` (the "+ ADD EXERCISE" button
*inside* the swap sheet, sentinel `__ADD_MODE__`) was also already correct —
it reads `logging_type` from the newly-created custom exercise's own form
data.

## Fix

1. `SwapExerciseData` gains a `loggingType` field (nullable — null only for
   the `__ADD_MODE__` sentinel, which never reaches a logging-type read since
   it's routed to `_openCreateAndAutoSwap` instead).
2. Both real `SwapExerciseData(...)` construction sites in
   `exercise_swap_sheet.dart` now pass `loggingType: ex['logging_type'] as
   String?`.
3. `_showSwapSheet`'s `onSelect` now reads
   `loggingType: swapEx.loggingType ?? ''` — an **empty string** floor, never
   `currentExercise.loggingType`. This choice is load-bearing: an empty
   string is exactly what `LoggingTypeResolver.resolve()` treats as "no
   direct value, fall through to the by-name library lookup" (`direct !=
   null && direct.isNotEmpty`). Falling back to the outgoing exercise's type
   instead would short-circuit that lookup and silently reintroduce this
   same bug for any future picker row missing `logging_type`.

## Verification

`test/contracts/swap_exercise_logging_type_behavioral_test.dart` — 5 tests:
- `SwapExerciseData` actually carries + defaults the new field correctly (2
  tests).
- **(a)** Through the real `ActiveWorkoutNotifier.swapExercise()`: a correct
  swapped-in type (`bodyweight_reps`) on an exercise replacing a `timed` one
  is trusted and actually flips `state.exercises[0].loggingType` — the exact
  reported bug, proven fixed end-to-end through the real provider + resolver.
- **(b)** An **empty** swapped-in type (simulating a picker row missing
  `logging_type`) falls through to a by-name `exerciseBox` lookup and
  resolves to that exercise's real seeded type (`bodyweight_reps`, distinct
  from both the outgoing `timed` and the resolver's ultimate `weight_reps`
  default) — proving `''` is the correct floor, not
  `currentExercise.loggingType`.
- A source-grep on `_showSwapSheet` specifically (not `_openCreateAndAutoSwap`,
  which has its own already-correct resolution) asserting it never contains
  `loggingType: currentExercise.loggingType` and does contain
  `swapEx.loggingType` — pins the one call site with no public seam to pump
  through a full widget test (`part of 'screen.dart'`).

**Mutated and run** (rule 21): reverted `swap_sheets.dart`'s onSelect to the
pre-fix `loggingType: currentExercise.loggingType`. 1 of 5 tests reddened —
exactly the source-grep test (`Expected: false, Actual: <true>` — "THE BUG —
using the OUTGOING exercise's loggingType..."). Tests (a)/(b) stayed green
because they construct `ExerciseData` directly and call `swapExercise()`
without going through `swap_sheets.dart`, so they could not see this
mutation — they instead pin that the underlying resolver mechanism (SoT
field carry-through + by-name fallback) behaves correctly, which the
source-grep test then confirms is what the actual call site invokes.
Restored the fix — all 5 tests passed again.

## Related

Recurrence of the writer/reader-drift class (`feedback_writer_reader_field_drift_recurring.md`)
— a value silently substituted from the wrong sibling record (outgoing vs.
incoming exercise) rather than sourced from the correct one. Not a
recurrence of a previously-diagnosed bug in `docs/diagnoses/INDEX.md` (grepped
for "logging_type"/"swap" — no prior instance of this exact substitution).
