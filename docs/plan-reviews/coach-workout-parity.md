---
branch: coach-workout-parity
scope: Coach workout parity slices 1a (one shared completion-bookkeeping step for every door, OI-379) and 1b (stricter chat-card completion rule + Train "Logged so far" + Complete button); merged together
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-workout-parity-bpass.md
---

# Plan-review record — coach workout parity (1a + 1b)

This branch merges two plans in one PR (1a plan §4: 1a alone would let the chat card's mark-on-any-save count a one-exercise day, permanently).

## Slice 1a: `docs/plans/coach-workout-parity-1a.md` (rev 4)

Three context-blind Sonnet review rounds, each with an exhaustive read-only command list.

**Round 1** (rev 1; A ground truth, B exposure). Both reviewers returned `needs-changes`.
- P1s:
  - `newlyCompleted` excluded rest, paused and terminal rows, so Active Workout stopped counting days it counts today (A-F1, B-F1, B-F7).
  - A +1 lost to a crash could never heal (B-F2).
- P2s: the success gate, the kill switch's false "exact restore" claim, backdated and non-IST dates, the hold-gate contract, and the repoint list.
- Folded into rev 2: the plan's §7.

**Round 2** (rev 2; A, B). Both reviewers returned `needs-changes`.
- P1s:
  - 1a alone over-counts permanently through the chat card. Fix: merge 1a and 1b together (B).
  - Legacy `wlog_<ms>` duplicates double a day. Fix: count distinct dates (A).
  - The owner was captured after the `logExercise` awaits. Fix: capture at entry (A).
- P2s: the restore-unsettled partial schedule, the writeservice allowlist, the helper's location, the null-progress mint, and masked mutations.
- Folded into rev 3: §8.

**Round 3** (rev 3; delta, both lenses). **CONVERGED** (no P0/P1).
- P2/P3 folded into rev 4 (§9):
  - the wlog clause on `newlyCompleted`;
  - the owner re-check;
  - the offline cost stated;
  - the record scope and push order;
  - the test seams;
  - the date precedent.

**Ground truth verified.** Every door, line and helper was checked against code by A in rounds 1 and 2 and re-checked in round 3:
- `markCompleted` lock and pre-write read: `workout_write_service.dart:596-631`.
- Hold-gate equivalence: `train_provider.dart:1071-1099`, against `activeHoldOrdinalFor`.
- `updateProgress` atomicity and sync: `user_repository.dart:1005-1018`.
- Synchronous reckon: `workout_repository.dart:336`.
- Every `type:'workout_log'` writer under `wlog_`: `workout_write_service.dart:647`, `sync_workout.dart:938`/`:1308`, `workout_repository.dart:763`, and the backfill migrator.
- The cloud ratchets: `weekly-recalc` `Math.max`, migration 156 `GREATEST`, and restore max-wins at `user_repository.dart:440`.

## Slice 1b: `docs/plans/coach-workout-parity-1b.md`

Context-blind Sonnet review rounds, each with an exhaustive read-only command list.

**Round 1** (rev 1; A ground truth, B exposure). Both `needs-changes`.
- P1s: the card's prompt row would never render without a `chatHistoryProvider` refresh (A-F2); the draft-state reader list was incomplete (`isSavedDraftStatus`, the card's `saved`, `hasNote`, `keepFailed`) (A-F3); a stale tile could complete and permanently count a past day (B-F1); moved and no-plan days' logs had no Train surface (B-F3); a counted rest-type row would read "Not counted" (B-F4).
- The plan's "the tap has no terminal guard" claim was false: the tap's display read already refuses terminal rows (A-F1, B-F2). Dropped; every decision now reads the raw row.
- P2/P3: name mismatch (0 of N), no-plan scope, `repairDone` asymmetry, in-progress session, one log source, repoint/reseed and docs lists, layering, paused, local-only prompt.
- Folded into rev 2 (§9). Founder approved the copy on 2026-11-10 (four questions, all recommended options).

**Round 2** (rev 2; A ground truth, B exposure). Both `needs-changes`.
- P1s: a future-dated full `log_set` would complete and count permanently (B2-F1); the done-before-rest change covered the chip but not the tap routing (A2-F1, B2-F6); a card retry after IST midnight would point at a Complete control that does not exist (A2-F2, B2-F2); the plan put a Hive write inside `ChatHistoryNotifier.build` (A2-F3); the `LOGGED TODAY` predicate could misfire on another selected week (B2-F3).
- P2/P3: tile refusal copy, the hero change had no label to replace, raw-read demotion, per-row log scan cost, missed test pins, `mintProgressIfMissing`, date-scoped in-progress hide, button for `completeNow`, rest-type divergence, lock window.
- Folded into rev 3 (§10). Two rev-2 mechanisms (the `LOGGED TODAY` block, the hero chip) were removed rather than patched; past-day and refusal lines reuse approved copy.

**Round 3** (rev 3; delta, both lenses). **CONVERGED** (no P0/P1). All five round-2 P1s closed as written; every `markCompleted(` call site and every `completion_prompt` reader re-checked; helper feasibility verified. P2/P3 folded into rev 4 (§11): the backstop's past-date prompt skip, the null session date, the day-label colour, `skipped`/`travel` stated.

**Ground truth verified (1b).** Checked against code across the three rounds: the draft-state readers (`ai_coach_provider.dart:1726-1990`, `workout_log_confirm_card.dart:17-140`), the backstop and its prompt writer (`tool_dispatcher.dart:206-215`, `:433-582`), the display vs raw schedule reads (`workout_schedule_read_service.dart:986-1020`, `:1318-1326`), Train's week data and row (`train_provider.dart:907-955`, `week_rows.dart:65-215`), the tap (`ai_coach_provider.dart:375-440`), and `hasInProgressSession` (`train_provider.dart:1377`).

**As built (1b).** The build added what the plan's tests surfaced, recorded in plan §12 and diagnose `24e630`: owner guards before the day decision in the card and the backstop (the account-change tests read the new account's row without them); `loggedPlannedExerciseCount` placed in `coach_day_completion.dart` (an import cycle ruled out `WorkoutReadService`); the tap kept the raw `?? 'Workout'` name; the COMPLETE WORKOUT button scales down instead of overflowing. 41 mutations, each red after four test gaps found by the first run were closed (the early-completed row, the pre-built chat thread, the sheet-scoped assertions, a text-scale case). None of this changes the converged design; the B-pass reviews the diff.
