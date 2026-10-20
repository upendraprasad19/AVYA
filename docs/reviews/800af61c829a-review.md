---
reviewed_at: 2026-10-20T12:07:28+05:30
staged_against: 800af61c829a
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: pending  # founder triage; every finding below is already fixed in this staged tree
---

# Code Review — log-exercise-batch2 (OI-356: UNDO toast, set-1 mirror, last-exercise emphasis; ship dark)

One fresh, context-blind Sonnet reviewer, read-only (exhaustive command list; no file edits, no scripts, no network; the full suite was running on the same tree, so mutations were proposed, not applied). It reviewed the staged diff `8812992b4995` (23 files) BEFORE the fixes; the hash in the frontmatter is the POST-fix tree. `flutter analyze lib/`: 59 infos, none in a touched file. Result: 1 P0, 0 P1, 3 P2, 0 false alarms. All four accepted and fixed in this batch, each mutation-proven (closure ledger rows BP1-BP4).

## Finding 1 — P0 — guard_without_its_mirror (tree shape)
- **file:line:** lib/features/train/screens/active_workout/screen.dart:165-182 (`_withLogUndoToast`, pre-fix)
- **claim:** the wrapper returned the bare `ListView` with no toast and a `Stack([ListView, Positioned])` with one. The element type at that `Expanded` slot changed on every show and clear, so Flutter rebuilt the list: a fresh `ScrollPosition` (no `PageStorageKey` in `lib/`, so the scroll jumps to the top), and cards beyond the cache extent were disposed with their typed, unlogged values. The 5 s Timer clears the toast, so this fires while the user is typing. The plan (§5.1) and plan-review round 2 described an always-present Stack; the built code did not match, and the source pins could not see it.
- **verification:** at review time, `git show :lib/features/train/screens/active_workout/screen.dart | sed -n 165,182p` showed `if (undo == null) return list;`; `grep -rn PageStorageKey lib | wc -l` = 0.
- **suggested-fix:** keep one Stack in LOG mode; add a screen-level or host-level widget test.
- **status:** accepted — fixed: `LogUndoToastHost` (log_undo_toast.dart) builds one `Stack(fit: expand)` with the list always at child 0 in LOG mode and the bare list with the flag OFF. Host tests in log_undo_toast_test.dart: scroll offset 1500 and the `Scrollable`'s and a row's State are identical across show and clear; no Stack when disabled. Mutations F1 (host returns the bare list when no toast, i.e. the shipped shape) and F1b (Stack with the flag OFF): RED.

## Finding 2 — P2 — missing_input (one-keystroke entry after a warm-up move)
- **file:line:** lib/features/train/screens/active_workout/exercise_card.dart `_mirrorFrom` (`if (source != _lastSourceIndex) { _baselineMirrorSource(data); return; }`)
- **claim:** after a warm-up toggle moved the source, the next keystroke only re-baselined, so a one-digit entry (the whole entry) never mirrored. Test 18b typed into reps first and could not see it.
- **verification:** read `_mirrorFrom`; `grep -n "18b" -A12` in the card test.
- **suggested-fix:** re-baseline when the warm-up flags change, not on the next keystroke.
- **status:** accepted — fixed: `_rebaselineIfSourceMoved` runs in `didUpdateWidget` (LOG mode only), so the rebuild that shows the toggle re-baselines; the keystroke-time path stays as a fallback. Card test 18c (toggle, type '8' into set 2, set 3 reads '8'). Mutation F2 (helper returns immediately): RED.

## Finding 3 — P2 — asserted_fixture_value (unreached follower branch)
- **file:line:** exercise_card.dart `_seedAppendedSets` (`from == _lastSourceIndex ||`)
- **claim:** every `+` test seeded from a follower or a prefilled set; the branch where `from` is the source (a one-set exercise) was never reached, so deleting it reddened nothing.
- **verification:** no mirror test with `sets: '1'`.
- **suggested-fix:** one-set test: type 60, `+`, new set 60, type 65, new set 65.
- **status:** accepted — fixed: card test 18d. Mutation F3 (`false ||`): RED.

## Finding 4 — P2 — writer_reader_drift (docs)
- **file:line:** docs/audit/open_issues.md (OI-358), docs/plans/log-exercise-batch2.md
- **claim:** OI-358, minted in this diff, cited pre-batch lines (`train_provider.dart:1610-1614`, `screen.dart:366,409`).
- **verification:** `grep -n "void addExercise"` and `grep -n "_exerciseKeys"` on the staged blobs.
- **suggested-fix:** re-baseline.
- **status:** accepted — fixed: OI-358 cites `train_provider.dart:1642-1646` and `screen.dart:438`/`:481`; the plan states both the pre-batch and the built lines.

## Lenses with no finding (reviewer's evidence, condensed)
- writer_reader_drift (code): every `checkedSets` writer (`toggleSet`, `logSets`, `unlogSets`, `swapExercise`, `removeExercise`, `removeLastSet`) checked against `visibleUndoRecord`; one `completeWorkout()` call site (finish_dialog), `onComplete` before it; SoT/diagnose line citations matched the staged blobs.
- function_exception_swallow: 0 added try/catch.
- blast_radius_mismatch: `account` correct (wardroom_copy.dart under `lib/core/**`).
- secrets_in_tree: 0 real hits.
- unawaited_no_error_sink: 0 added `unawaited(`; the Timer checks `mounted` + generation and is cancelled in dispose, the completion listener and `_clearLogUndo`.
- guard_without_its_mirror: each guard followed to its applier (`undoRecordFor` -> `_showLogUndo`; `unlogSets` false -> `_onLogUndo` still clears; `visibleUndoRecord(isSaved)` pairs with `unlogSets(isSaved)`; flag OFF identity).
- missing_input / asserted_fixture_value: null record, out-of-range index, zero sets, empty sets and exercise list handled; three-exercise identity fixtures.

## Proposed mutants (run by the author after the fixes)
R1 `trim()` dropped in `mirrorTargets` -> RED 1; R2 `if (!removed) return false;` deleted -> RED 1; R3 `_mirrorFrom` moved below the `isSetChecked` return -> RED 11; R4 `logToastText` counts warm-ups -> RED 1. R5 duplicates the author's P7. R6 (Timer generation check) and R7 (`onComplete` order) are source pins only: the screen State is not pumped.

## Founder triage notes
<filled in by founder during triage>
