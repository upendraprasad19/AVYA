---
reviewed_at: 2026-07-18
staged_against: 3c9f18f0d42d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, w3_3_correctness]
findings_count: 1
verdict: accepted
---

# Code Review — 3c9f18f0d42d (Batch 11-A W3.3 id-keyed history)

Fresh context-blind Sonnet B-pass over the staged diff (895 lines). One P1 finding;
all other lenses clean after ground-truth verification. The P1 was **fixed in-batch**
(not deferred) — the fix threads the library id through the manual swap/add UI paths,
making the SoT/CLAUDE.md claim true rather than softening it.

## Finding 1 — P1 — w3_3_correctness (manual swap/add paths dropped the id) — **FIXED**

- **file:line:** `lib/features/train/screens/active_workout/swap_sheets.dart:13,53,137` +
  `lib/features/train/providers/train_provider.dart:259` (`SwapExerciseData`)
- **claim:** The three manual `ExerciseData(...)` builders (add-exercise, swap, create-and-swap)
  constructed without `exerciseId:`, so a manually-swapped/added exercise always logged
  `exercise_id: null` — even when a real library id was available. `SwapExerciseData` had no
  id field; the add-path map's `id` was unread. This contradicted the SoT/CLAUDE.md claim that
  the "swap" case (the case the feature is named for) carries the id.
- **verification:** Read `swap_sheets.dart` (all 3 builders omit `exerciseId:`), `SwapExerciseData`
  (`train_provider.dart:259-269`, fields name/detail/emoji only), `exercise_swap_sheet.dart:299,321`
  (builds `SwapExerciseData(name, detail)` from `ex`), and `ExerciseRepository.getAll()`
  (`exercise_repository.dart:15-26` — seed rows **already carry `id`**, Hive key == id), confirming
  the id IS available at every construction site (so threading is a real win, not dead plumbing).
- **resolution (fixed in commit):**
  - `SwapExerciseData` gained an optional `String? id`.
  - `exercise_swap_sheet.dart` (library + custom list builders) pass `id: ex['id']`.
  - `swap_sheets.dart` threads `exerciseId:` at all three builders — add-path `exerciseData['id']`,
    swap-path `swapEx.id`, create-swap `newExercise['id']` (usually null for a brand-new custom →
    name fallback, which is correct).
  - New drift guard `test/contracts/exlog_exercise_id_swap_threading_test.dart` pins the field +
    the three threadings; SoT `exercise_id_history` + `plan_engine/CLAUDE.md` wording updated to
    match.
  - All null-safe; zero behavior change when `enable_exercise_id_history` is OFF (ship-dark).
- **status:** fixed

## Lenses that returned clean (verified, not assumed)

- **writer_reader_drift** — writer `logExercise` emits `'exercise_id'`; reader
  `ProgressionResolver.resolve` reads `log['exercise_id']` (same key). `TrainingHistoryAnalyzer`
  intentionally excluded (still name-keyed, per Round-1 decision). Gate 19 `_expectedEmitFields`
  extended for `exercise_id` in the same commit → no false-positive.
- **function_exception_swallow** — no `.functions.invoke(` in the diff.
- **blast_radius_mismatch** — `enable_exercise_id_history` defaults OFF; every gated branch
  (`lastSessionById`/`allById`/`planId`/`byId`/graded-union) collapses to the verbatim name-only
  path → byte-identical when OFF. WRITE side is unflagged-additive (new optional Hive key, never
  synced to cloud).
- **secrets_in_tree** — no credential-shaped literal in the diff.
- **unawaited_no_error_sink** — no new `unawaited(` added.
- **w3_3_correctness (Hive-local)** — cloud `exercise_id` stays name-derived
  (`sync_workout.dart:198`); `_restoreExerciseLogs` reconstructs the Hive row WITHOUT an
  `exercise_id`; pinned by `sync_exlog_no_library_id_test.dart`.
- **w3_3_correctness (sticky/coach/dedup)** — sticky reuse keyed on the name-derived exlog key
  (no cross-exercise collision); coach stamps only a resolvable library id; the graded session
  union de-dupes by calendar day so a doubly-indexed row can't double-count.

## Founder triage notes

Self-triaged under auto-mode: the single P1 was fixed in-batch (threaded the id through all
three manual paths + a drift guard). Verdict accepted.
