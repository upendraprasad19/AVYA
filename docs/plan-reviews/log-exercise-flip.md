---
branch: log-exercise-flip
date: 2026-10-20
blast_radius: account
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: accepted  # founder triage 2026-10-21 (chat)
bpass_review: docs/reviews/0b00dc45c72b-review.md
---

# Plan-review record: one-LOG-per-exercise goes live (RE-OPEN, faded prefill, FINISH guard, flip)

Plan: [`docs/plans/log-exercise-flip.md`](../plans/log-exercise-flip.md). Execution mode: inline (plan header). Every round used two fresh context-blind reviewers: one on ground truth (A) and one on exposure/UX (B). Each brief carried `docs/agent_brief_preamble.md`, lenses from `docs/audit/LENS_REGISTRY.md`, and a read-only command list. The coordinator checked every finding against the code before acting (L17).

Revisions 1 to 6 of the plan were not committed. This record is their history.

## Round 1 (revision 1): not converged

- **R1A** (ground truth): 0 P0, 1 P1, 5 P2, 4 P3.
- **R1B** (exposure): 0 P0, 2 P1, 8 P2, 5 P3.

Material findings:
- The plan claimed a workout resumes from `active_session`. That key is only the coach snapshot (`active_workout_persistence.dart:3-37`), and session state is in-memory.
- There is no way back after the 5 s UNDO.
- LOG saves prefilled values the user never looked at (phantom sets).
- There is no screen-level test of the flip.
- `main` was red (PR #134 must land first).
- The `bpass` sequencing was wrong.
- One mutation did not compile.
- The obligations list was incomplete.

**Founder decisions (2026-10-20):**
- device check after merge;
- keep the OFF path as the kill switch, with an OI to remove it;
- add AMEND, named RE-OPEN;
- faded prefill with a subline and no alert.

**Response:** revision 2.

## Round 2 (revision 2): not converged

- **R2A** (ground truth): 0 P0, 2 P1, 12 P2, 7 P3.
- **R2B** (UX): 1 P0, 5 P1, 8 P2, 4 P3.

**P0 (R2B-01 / R2A-01):** AMEND, then FINISH, silently drops a logged exercise. `unlogSets` unchecks the sets, and `completeWorkout` skips unchecked sets (`train_provider.dart:2010`).

**P1s:**
- A second tap after a re-open re-LOGs.
- The LOGGED button is hard-disabled.
- "Typed = gold" is untrue for reps and logged sets, and gold already means the TRY suggestion.
- A card-local fade is lost or inverted on re-entry.
- The "LAST SESSION" provenance claim is untrue.
- The two-line button does not fit at 320 dp.

**Founder decisions (2026-10-20):**
- fix every issue in one batch and review again;
- the FINISH dialog lists the exercises that will not be saved;
- faded vs normal colouring only;
- subline copy `{kg} KG · PREFILLED`.

**Response:** revision 3. It added the U-D FINISH guard, the shared guard stamp on re-open, a 700 ms re-open window, provider-held fade state, `minHeight` with `FittedBox`, a Semantics hint, the dev-panel pin, and handler ordering.

## Round 3 (revision 3): not converged, 0 P0

- **R3A** (ground truth): 0 P0, 2 P1, 6 P2, 6 P3. Baseline `log_exercise_card_test.dart` 27/27 green on 7cfa485. Flutter facts read from the 3.41.4 SDK source.
- **R3B** (UX/exposure): 0 P0, 5 P1, 9 P2, 6 P3.

**P1s:**
- `selectAllOnFocus` does not select on a user tap (R3A-01). A coordinator spike confirmed it, and also showed that `TextField.onTap` setting the full selection works on a real `tester.tap`.
- "Will not be saved" uses `isExerciseDone`, not save semantics (R3A-02, R3B-01). `+` after LOG and all-warm-up exercises get it wrong.
- A re-opened-and-forgotten exercise is not told apart from a deliberate skip (R3B-02).
- A conditional Semantics wrapper would remount the field on the first keystroke (R3B-03, R3A-04, the batch-2 tree-shape class).
- Re-init leaves the fade and the text out of step, because typed-unlogged values are not captured (R3B-04, R3A-03).
- The re-open text and semantics show in review mode (R3B-05).

**P2s:**
- no feedback after an accidental re-open;
- dialog overflow;
- header and dialog counts disagree;
- the PREFILLED reading;
- the TalkBack label;
- reps and bodyweight have no signal;
- three-part key cleanup;
- the S1 rebuild, Hive I/O and scroll;
- non-discriminating mutations and missing ones;
- the wording for skips;
- A12 gaps;
- the §0 history claim.

**P3s:**
- cites;
- `isFaded` signature;
- `SetInputRow` API;
- import cycle;
- SoT parity across concepts;
- non-empty mirror marks;
- one-frame flash;
- subline width;
- superset LOG guard;
- `clearSuggested` no-op;
- rollback caveats;
- mirror adoption.

**Response:** revision 4. Plan §0 maps every finding to its resolution. No new founder decision was needed: each resolution keeps the round-1/2 decisions.

## Round 4 (revision 4): not converged, 0 P0

- **R4A** (ground truth): 0 P0, 1 P1, 3 P2, 6 P3. 82 existing card/logic/controller tests green on 7cfa485; the parity and deferral gates pass; throwaway spikes for Semantics, select-all taps and 320 dp layout.
- **R4B** (UX/exposure): 0 P0, 1 P1, 6 P2, 8 P3. Throwaway probes for Semantics and contrast.

**P1 (both reviewers, independently):** the revision-4 button Semantics (`excludeSemantics: true` without `onTap:`) removes `SemanticsAction.tap`, so TalkBack cannot activate LOG or LOGGED. The shipped UNDO toast already has the same defect (`log_undo_toast.dart:84-88`).

**P2s:**
- a cleared prefill is resurrected as NORMAL after a re-init (restore skips null captures; both reviewers);
- 320 dp × 1.5/2.0 overflows at baseline on the LAST row, and the finish-dialog duration row overflows;
- the save predicate was presence-pinned only;
- an accidental second tap on the last exercise re-opens it;
- zero-set COMPLETE credits the day (pre-existing);
- the progress percent is NaN when every set is a warm-up;
- `· PREFILLED` labels the user's own typed set 1 via the followers.

**P3s:** second-tap timing; the `onTapHint` property; `scrollable` on OFF; vacuous no-change check; wording for all-warm-up; name-keyed re-open; marks on hidden fields; a weakened review-mode test; missing mutations and pins; the re-open stamp shorter than the focus scroll; field labels for TalkBack; `logSets` during a save; typing latency; followers after a re-init; A12 gaps; web auto-deploy from `main`; no closure entry for reps/bodyweight.

**Coordinator checks:** the restore loop (`exercise_card.dart:158-176`), the UNDO Semantics (`log_undo_toast.dart:84-88`) and the `vercel.json` `ignoreCommand` were read directly and match the findings.

**Response:** revision 5. Plan §0 maps every finding. No new founder decision is needed. Two new obligations: a minted OI for zero-set completion credit, and the UNDO Semantics fix in this batch.

## Round 5 (revision 5): 0 P0, 0 P1

- **R5A** (ground truth): 0 P0, 0 P1, 2 P2, 7 P3.
- **R5B** (UX/exposure): 0 P0, 0 P1, 5 P2, 5 P3.

Reviewer spikes confirmed four points:
- **Button Semantics:** `onTap:` + `excludeSemantics` gives one tap action and no double-fire.
- **LOG-mode restore:** the null->'' restore breaks no seeding (duration controllers start empty; swap wipes the slot).
- **U-D1b is buildable:** a real awaited `completeWorkout` wrote `exlog_*` rows (A=3, D=3 of 4; B and C absent).
- **Select-all and identity:** select-all on tap works, and `EditableTextState` identity holds across keystrokes.

**P2s:**
- the U-D1b helper mutation cannot redden a relative parity check;
- protections without a mutation;
- the guard-line `maxLines` cuts the names;
- no TalkBack confirmation for LOG or RE-OPEN;
- unit labels (SEC vs MIN; doubled on blank);
- followers stop following after a re-init (the amend path);
- typed-but-unlogged reads as a skip.

**P3s:**
- `Wrap` spacing changes OFF;
- hint wording collides with TRY;
- a dead tap after an accidental re-open;
- web rollback path;
- ledger and completion-screen wording;
- stale S1 copy;
- Fraunces priming and the harness weight parameter;
- hidden-field marks and an overstated "never lost";
- the registry `_completing` sentence and cites;
- live-state evaluation and the progress clamp.

**Response:** revision 6. Plan §0 maps every finding. No new founder decision is needed (the typed line and TalkBack feedback apply "FINISH lists unsaved" and the plan's own accessibility commitments). Revision 6 adds three small mechanisms: the TalkBack announcement and live region, the mirror re-seed, and the typed-unsaved line. A delta round reviews them.

## Round 6 (revision 6, delta review, both lenses): converged

**R6:** 0 P0, 0 P1, 2 P2, 6 P3. The reviewer's verdict: "converged after R6-01 and R6-02 are folded in as plan text".

Spikes confirmed:
- `SemanticsService.sendAnnouncement` (`semantics_service.dart:81`) and `tester.takeAnnouncements()` exist, so SM2 is buildable.
- A `label`/`hint` null<->string toggle keeps `EditableTextState` identity.
- The unit strings are KG/REPS/SEC/MIN/KM, as `set_input_row.dart:144-184` passes them.
- The re-seed is implementable at init time and does not touch the batch-2 mirror tests.
- `typedUnsaved` has no false positive except the logged all-warm-up case (R6-03).
- With a fitting label, `Wrap(spacing: 0)` lays out identically to the Row.

**P2s:**
- U-D5's `spacing: 6` mutation did not redden at 360 dp, because the baseline Row already overflows under the test font. The check moves to 390 dp and compares tops.
- The re-seed's text-equality clause was unprotected. P9c adds coverage, with two mutations.

**P3s:** `typedUnsaved` restricted to unchecked sets; `unawaited` on the announcement; field label/hint mutations and a reps mutation; naming list; U-D1b fixture wording; two re-seed edge cases stated; live-region re-announce on logged-set edits (A12).

**Response:** revision 7 folds in every round-6 finding as plan text. No new mechanism and no new founder decision, so no further round is needed.

**Convergence:**
- Six rounds, eleven context-blind reviews.
- Round 5 had 0 P0 and 0 P1 from both reviewers. Round 6, a delta review of the only new mechanisms, had 0 P0 and 0 P1, with test-spec P2s only.
- Ground truth was verified by reviewer spikes in rounds 3 to 6, and by the coordinator's selectAllOnFocus/onTap spike.

## Round 7 (revision 8, delta review of U-E, both lenses): converged

The founder folded OI-361 (a workout with zero logged sets must not complete) into this batch after round 6, so revision 8 added unit U-E on both flag paths. A fresh context-blind reviewer read U-E against the code and the half-written worktree diff.

**R7:** 0 P0, 0 P1, 3 P2, 3 P3. Verdict: "sound in design; fold the three P2s in and U-E is converged".

Spikes confirmed:
- A real awaited `completeWorkout` through `setUpHiveForTests` wrote no Hive key and left `total_workouts_done` null for zero sets and for warm-up-only, and completed fully with one saveable set (exlog, wlog and schedule rows, `total_workouts_done == 1`).
- `fakeAsync` does not move `elapsedSeconds` (the timer reads `DateTime.now()`); `fa.periodicTimerCount` reads 1 before and 1 after a guarded `completeWorkout` that followed a real `startWorkout`.
- The guard as the first line is safe: `completeWorkout` has one lib caller (`finish_dialog.dart`), and the only tests that call it use saved values.
- An OFF-mode checker always has captured values before a check, so a real OFF user is never wrongly blocked.

**P2s:**
- R7-01: the OFF blocked dialog does not scroll and can overflow at 320 dp with a large font and the keyboard up.
- R7-02: `submitWorkoutDraft` calls `markCompleted` for a chat draft with no sets (the same zero-set credit class); the plan's "the coach path always has a set" was true for only two of three coach callers.
- R7-03: U-E1's timer assertion was unbuildable, and the guard placement had no mutation.

**P3s:** the block hid the re-opened/typed lines and its wording was untrue for an all-warm-up session (R7-04); the notifier guard is dead behind the modal dialog and the closure's side effects run first (R7-05); two U-E3 cases (R7-06).

**Response:** revision 9 maps every finding (plan §0). R7-02 is closed in this batch with one shared predicate, `draftHasLoggableSet`, used by `submitWorkoutDraft` and the confirm card, and tests U-E4/U-E5. No new founder decision: R7-02 applies the founder's "zero sets logged should not be allowed" to the third completion caller. The resolutions are plan text plus one small guard on an existing path, so no further round is needed.

**Convergence:** seven rounds, twelve context-blind reviews. Rounds 5 to 7 had 0 P0 and 0 P1.

## B-pass (staged diff, after convergence)

One fresh, context-blind Sonnet reviewer read the staged diff (`ea6bc3a330d3`) under an exhaustive read-only
command list: 0 P0, 0 P1, 1 P2, 6 P3 (`docs/reviews/0b00dc45c72b-review.md`, named by the post-fix staged hash).
Fixed in this batch, each mutation-proven (8 mutants, all RED): the chat draft predicate now counts only sets that
carry a value (P2); a throwing save resets `_completing`; re-open marks leave with a swapped or removed exercise; the
duration/distance typed-not-logged cases are tested; the COMPLETE live re-check closes the dialog instead of a dead
button. One false alarm (the flag's catch is unreachable outside tests: `configBox` is shared and never closed) and
one process note (this record lands in its own follow-on commit because it cites the review file). Founder triage
2026-10-21 (chat): accepted.
