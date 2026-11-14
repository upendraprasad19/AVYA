---
reviewed_at: 2026-10-19T00:00:00+05:30
staged_against: 0ca89ed08961
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — active-workout-log-exercise (U1a, one LOG per exercise, ship dark)

One fresh, context-blind Sonnet reviewer, read-only (exhaustive command list; no file edits, no scripts, no network), on the staged diff (22 files) before the fixes. `flutter analyze lib/` clean in touched files; the 3 new test files green (43). Result: 0 P0, 0 P1, 6 P2. All six accepted and fixed in this batch; the staged hash above is the POST-fix tree.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/features/train/services/log_exercise_logic.dart (`if (identical(after, before)) return noop`)
- **claim:** the noop branch was reached by no test; deleting it would let a stale LOG stamp the 400 ms guard with no advance and swallow the next real LOG on another card.
- **verification:** `grep -n "stale indexes" test/contracts/active_workout_set_logging_behavioral_test.dart`
- **suggested-fix:** controller test with stale indexes asserting noop and an un-armed guard.
- **status:** accepted — fixed: tests "stale indexes ... never stamp the guard" and "a partial LOG does not stamp the guard"; mutations M14 (noop line removed) and M19 (stamp on every LOG) RED.

## Finding 2 — P2 — guard_without_its_mirror (screen applies the advance)
- **file:line:** lib/features/train/screens/active_workout/screen.dart `_onLogExercise` (`if (outcome.clearFocus)`, partner reveal)
- **claim:** nothing proved the screen applies `clearFocus` / `revealPartner`; deleting the block left every test green.
- **verification:** `grep -n "the screen applies the outcome" test/contracts/active_workout_set_logging_behavioral_test.dart`
- **suggested-fix:** source pin inside the `_onLogExercise` slice, or extract.
- **status:** accepted — fixed with a source pin (presence only; the screen State is not pumpable, the decision itself is behaviourally tested on the controller). M15 (block deleted) RED. Recorded as presence-only in the closure ledger.

## Finding 3 — P2 — guard_without_its_mirror (review mode)
- **file:line:** lib/features/train/screens/active_workout/exercise_card.dart `_onFieldChanged`
- **claim:** in review mode (`isSaved`) a keystroke on a logged set was captured, so the header volume could disagree with the saved log.
- **verification:** `grep -n "if (data.isSaved) return;" lib/features/train/screens/active_workout/exercise_card.dart`
- **suggested-fix:** `if (data.isSaved) return;` + card test.
- **status:** accepted — fixed; card test "review mode: a keystroke on a logged set records nothing"; M16 RED.

## Finding 4 — P2 — writer_reader_drift (stored value differs from visible value)
- **file:line:** lib/features/train/screens/active_workout/exercise_card.dart `_buildLogRow` failure scan
- **claim:** after an invalid edit to a logged set the stored value silently differed from the field while the row read LOGGED.
- **verification:** `grep -n "for (var i = 0; i < numSets; i++)" lib/features/train/screens/active_workout/exercise_card.dart`
- **suggested-fix:** make the divergence visible.
- **status:** accepted — fixed: the row scans EVERY set and shows the blocked label (tap focuses the field) instead of LOGGED until the value validates; extended card test "edit after LOG"; M17 (scan only unchecked) RED.

## Finding 5 — P2 — missing_input (flip precondition gap)
- **file:line:** exercise_card.dart `_initControllers` (duration/distance seeded empty, e8f95e); docs/ship_dark_pending_review.yaml precondition 1
- **claim:** duration and distance are blank for EVERY user, so timed/cardio/distance exercises block LOG on every set; the precondition named only the weight mirror.
- **verification:** `grep -n "duration AND distance" docs/ship_dark_pending_review.yaml docs/audit/open_issues.md`
- **suggested-fix:** widen the batch-2 mirror scope.
- **status:** accepted — fixed in docs: OI-356 scope, the plan's batch-2 line and flip precondition 1 now cover weight, duration and distance.

## Finding 6 — P2 — docs consistency
- **file:line:** docs/plan-reviews/active-workout-log-exercise.md (DRAFT sentence); docs/plans/active-workout-log-exercise.md status line
- **claim:** two stale sentences contradicted the staged state.
- **verification:** `grep -n "DRAFT\|plan only" docs/plan-reviews/active-workout-log-exercise.md docs/plans/active-workout-log-exercise.md`
- **suggested-fix:** update both.
- **status:** accepted — fixed.

## Lenses the reviewer reported clean
function_exception_swallow (no `invoke(` in the diff); blast_radius_mismatch (account via `lib/core/copy/wardroom_copy.dart`, matches the record); secrets_in_tree (no credential-shaped literal); unawaited_no_error_sink (un-awaited `writeState` matches the pre-existing `_persistActiveState` pattern; the new `Future.delayed` is `mounted`-guarded); missing_input (all helpers, copy constants, OIs and the mockup exist with the assumed shape); asserted_fixture_value (`1440 KG LIFTED` = 3 x 60 x 8, TextField indices, the 5 OFF tiles = 3 checks + 2 steppers, all recomputed).

## Founder triage notes
Founder triage 2026-10-20 (chat: "Accept both"): every finding accepted as written; the fixes already landed in this batch stand.
