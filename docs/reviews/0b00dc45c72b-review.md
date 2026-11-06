---
reviewed_at: 2026-10-20T23:30:00+05:30
staged_against: 0b00dc45c72b
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
---

# Code Review — log-exercise-flip (one LOG per exercise goes live: RE-OPEN, faded prefill, FINISH guard, OI-361)

One fresh, context-blind Sonnet reviewer read the staged diff `ea6bc3a330d3` (42 files) under an exhaustive
read-only command list (read-only git, file reads, `flutter analyze lib/`, four named test sets; no scripts, no
network, no edits). It ran analyze (0 errors, 0 warnings) and the four test sets (175 passed). Result: 0 P0,
0 P1, 1 P2, 6 P3. The coordinator verified each against the code before acting; five were fixed and
mutation-proven on the post-fix tree, whose hash names this file. The review was taken on `ea6bc3a330d3` and the
file was renamed after the fixes moved the hash, and again after the OI-363 mint and the founder triage edits (precedent: `5f77a4654f04-review.md`).

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/features/ai_coach/services/conversational_log_handler.dart:238-264
- **claim:** `draftHasLoggableSet` asked only whether a set OBJECT exists. A cardio draft with no duration and no distance, or a lift whose sets are all blank (the edit sheet writes `DraftSet(weightKg: null, reps: null)` when both fields are cleared), still produced a 0×0 set, so CONFIRM stayed enabled and `markCompleted` ran: the OI-361 harm through the chat door.
- **verification:** `sed -n 238,264p lib/features/ai_coach/services/conversational_log_handler.dart`
- **suggested-fix:** count a set only when it carries weight, reps or duration above 0 (cardio: duration or distance); use it for both the predicate and the written sets.
- **status:** accepted — fixed: `draftExerciseSets` keeps only sets with weight, reps or duration above 0, and cardio only with a duration or distance; `draftHasLoggableSet` reads it. Test U-E4 "all-blank sets are not loggable and are never written". Mutations RED: blank lift sets written (BF1a), blank cardio written (BF1b).

## Finding 2 — P3 — unawaited_no_error_sink / guard_without_its_mirror
- **file:line:** lib/features/train/providers/train_provider.dart:1577-1580, :1980
- **claim:** `_completing` was reset only in `startWorkout`. If the un-awaited save threw after setting it, LOG (newly guarded), UNDO and RE-OPEN all stayed silent no-ops for the rest of the session.
- **verification:** `grep -n "_completing" lib/features/train/providers/train_provider.dart`
- **suggested-fix:** reset `_completing` when the save throws.
- **status:** accepted — fixed: the save body moved to `_persistCompletion()`; `completeWorkout` wraps it in `try { … } catch (_) { _completing = false; rethrow; }` (the error still propagates as before). Test "completeWorkout throws (no Hive): _completing resets, LOG works". Mutation RED: catch without the reset (BF2).

## Finding 3 — P3 — function_exception_swallow
- **file:line:** lib/features/train/services/log_exercise_flags.dart:16-23
- **claim:** with the default flipped to ON, the `catch` still returns `false` (the old path); a Hive read error on `configBox` mid-session would silently switch the screen to check tiles.
- **verification:** `sed -n 14,25p lib/features/train/services/log_exercise_flags.dart`
- **suggested-fix:** return `true` in the catch, or cache the first read.
- **status:** false_alarm — `configBox` is a SHARED box (`HiveService._sharedBoxNames`, opened by `init()` before `runApp`) and is never closed: `HiveUserSession.closeAll` closes only the user-scoped roots (`hive_user_session.dart:412-420`). The catch is reachable only before init, i.e. in pure unit tests, which is what the plan specified (§4 table, test F0).

## Finding 4 — P3 — writer_reader_drift
- **file:line:** lib/features/train/providers/train_provider.dart:1605-1627, swapExercise, removeExercise
- **claim:** `reopenedExercises` is keyed by name and was never pruned: a swap A→B→A (or a removed exercise re-added) mislabelled the new A as "Re-opened, not logged again".
- **verification:** `sed -n 1691,1750p lib/features/train/providers/train_provider.dart`
- **suggested-fix:** drop the name when the exercise leaves its slot.
- **status:** accepted — fixed: `swapExercise` and `removeExercise` remove the outgoing name in the same state change. Duplicate names in one session still crash the screen (OI-358), as stated in plan §5. Tests in "re-open marks leave with their exercise". Mutations RED: swap keeps the mark (BF4a), remove keeps the mark (BF4b).

## Finding 5 — P3 — asserted_fixture_value (test gap)
- **file:line:** lib/features/train/services/log_exercise_logic.dart (`_hasTypedUnloggedValue`)
- **claim:** the duration and distance branches of the typed-not-logged detector were never exercised.
- **verification:** `grep -n "durationSeconds\|distanceKm" test/features/train/log_exercise/log_exercise_logic_test.dart`
- **suggested-fix:** add timed/cardio cases, plus a suggested duration.
- **status:** accepted — test "timed and cardio: a typed duration / distance is typed; a suggested one is skipped". Mutations RED: duration never typed (BF5a), distance never typed (BF5b).

## Finding 6 — P3 — missing_input / process
- **file:line:** docs/plan-reviews/log-exercise-flip.md (untracked)
- **claim:** the plan-review record was not staged and still says `bpass: pending`.
- **verification:** `git status --short | grep '^??'`
- **suggested-fix:** stage it; set bpass after triage.
- **status:** accepted (process) — deliberate: the record cites this file, and citing it from a staged `docs/plan-reviews/` file moves the hash it names, so it lands in its own follow-on commit (code-review SKILL §3 step 3). `check_plan_review_record_exists.dart` needs it on the branch only by the merge. `bpass:` is set from this file's verdict after founder triage.

## Finding 7 — P3 — guard_without_its_mirror
- **file:line:** lib/features/train/screens/active_workout/finish_dialog.dart:168-173
- **claim:** the closure's live re-check returned silently, leaving an enabled COMPLETE that does nothing (unreachable today behind the modal dialog, but a dead state if it ever fires).
- **verification:** `sed -n 160,180p lib/features/train/screens/active_workout/finish_dialog.dart`
- **suggested-fix:** pop the dialog instead.
- **status:** accepted — fixed: the re-check pops the dialog before returning (nothing else runs; FINISH reopens it with the current state). U-E2b now asserts the dialog closes with nothing completed, the duration not applied and the coach snapshot kept. Mutation RED: no pop (BF7).

## Lenses that returned clean (reviewer's evidence, abridged)
- writer_reader_drift: `copyWith` threads both new fields; swap/remove/removeLastSet re-index `suggestedInputs` with the field suffix kept; the dialog, header and `completeWorkout` all read `saveableSetIndexes` (U-D1b parity passed); fixture counts recomputed by hand (10/16, `D 3/4`).
- function_exception_swallow: no new `.invoke(`, no new try/catch in code (the one touched catch is finding 3).
- blast_radius_mismatch: no staged path above account.
- secrets_in_tree: 0 hits over `+` lines.
- unawaited_no_error_sink: one new `unawaited(SemanticsService.sendAnnouncement(…))`, a fire-and-forget channel send.
- missing_input: fonts, helpers and copy constants exist; tests read `lib/` from the repo root.
- asserted_fixture_value: `1440 KG`, `1460 KG LIFTED`, `3/6`, `0 / 0 SETS` recomputed; absence tests have positive controls.
- OFF path: the only `SetInputRow` caller is `exercise_card.dart`; OFF changes (always-present Semantics label, scrollable only when blocked, the duration Wrap, the LAST-row Flexible) are pinned by L1/L2/U-D3/U-D5.

## Proposed mutants (reviewer) and their runs
1 (warm-up clause), 2 (zero-set guard), 3 (`_completing` in logSets), 5 (2-part re-index), 7 (edited key never cleared), 8 (re-open done check): each already in the batch's mutation run, all RED (closure ledger). 4 (`removeAll(clear)` emptied): covered by the same tests as mutant 7. 6 (duration never typed): was the finding 5 gap, now RED (BF5a). 9 (stricter `draftHasLoggableSet`): was the finding 1 gap, now pinned by the blank-set test.

## Founder triage notes
Founder triage 2026-10-21 (chat): accepted on the coordinator's recommendation. Findings 1, 2, 4, 5 and 7 fixed in this batch and mutation-proven; finding 3 a false alarm (the flag catch is unreachable outside tests); finding 6 a process note (the plan-review record lands in its own follow-on commit).
