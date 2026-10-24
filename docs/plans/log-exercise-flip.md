# Plan: one-LOG-per-exercise goes live: RE-OPEN, faded prefill, FINISH guard, then flip `enable_log_exercise_button` to default ON

Branch `log-exercise-flip`, base `main` a909cdb (PR #134 merge; drafted on 7cfa485). **Revision 9** (rounds 1 to 6 converged; U-E added after the founder folded OI-361 in; delta round 7 on U-E: 0 P0, 0 P1, folded in below). Execution mode: inline, one worktree, no subagent builders. Five units ship in ONE commit and ONE PR (founder 2026-10-20: "fix all issues once and review again", one batch; "fold OI-361 into flip batch"): **U-A RE-OPEN**, **U-B faded prefill + subline**, **U-D FINISH guard**, **U-E zero-set block (OI-361)**, **U-C the flip**.

**Tier: `account`** (R2A-07). New copy lands in `lib/core/copy/wardroom_copy.dart` (`docs/blast_radius.yaml:550`, `lib/core/**`); everything else is `feature`.

- So `check_plan_review_record_exists.dart` requires `docs/plan-reviews/log-exercise-flip.md` at the merge, with `review_rounds >= 2`, `ground_truth_verified` and `verdict: converged`.
- `bpass: accepted` is required only at `platform`+. The record therefore says `bpass: pending  # result` until the founder triages the review file (the batch-2 incident, PR #134).
- The B-pass runs regardless (CLAUDE.md 4.3, 4.12.4).

## 0. Review history and founder decisions

Revisions 1 to 6 of this file were never committed: the branch has no commits yet. The findings and dispositions of every round are kept in the plan-review record `docs/plan-reviews/log-exercise-flip.md`, which lands in the batch commit with this plan (R3A-08).

**Round 1** (R1A ground truth 0/1/5/4, R1B exposure 0/2/8/5; P0/P1/P2/P3):
- the false "`active_session` resume" claim (fixed, §5);
- no way back after the 5 s UNDO (-> U-A);
- LOG saves prefilled phantom sets (-> U-B);
- no screen test (-> S1);
- main red (PR #134 first);
- bpass sequencing, a mutation that did not compile, and missing obligations.

**Round 2** (R2A 0/2/12/7, R2B 1/5/8/4): the P0 was RE-OPEN then FINISH silently dropping a logged exercise, which led to U-D. Every round-2 finding is dispositioned in the record.

**Round 3** (R3A 0/2/6/6, R3B 0/5/9/6). Every finding was checked against the code (L17), and select-all was checked with a throwaway spike (below). Disposition:

| Finding | Resolution in revision 4 |
|---|---|
| R3A-01 (P1): `selectAllOnFocus` does not select on a user tap. On a tap `requestKeyboard` flags the focus change internal, so `editable_text.dart:4779-4783` skips select-all. | **Spike 2026-10-20** (throwaway, deleted), Flutter 3.41.4, real `tester.tap`: `selectAllOnFocus: true` -> `TextSelection.collapsed(offset: 2)`; `onTap: () => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length)` -> `(0, 2)`; a second tap after typing -> collapsed. §2 uses `TextField.onTap`, only while the field is faded. |
| R3A-02 / R3B-01 (P1): "will not be saved" is false for `+` after LOG (sets 1-3 ARE saved) and misses an all-warm-up "done" exercise (saves nothing) | §3: the predicate is what `completeWorkout` does, extracted as `ActiveWorkoutData.wouldSaveSet` and CALLED by `completeWorkout` (one predicate, no drift). Partly logged exercises get their own wording. |
| R3B-02 (P1): a re-opened-and-forgotten exercise reads the same as a deliberate skip, so the warning habituates | Provider `reopenedExercises` (§1). Its own line, in the stronger colour, above the calm skip line (§3). |
| R3A-04 / R3B-03 (P1): a conditional `Semantics(hint)` wrapper remounts the `EditableText` on the first keystroke (the batch-2 tree-shape P0 class) | §2: the wrapper is ALWAYS present on every field, in both modes (`hint: faded ? … : null`). Test P8 asserts `EditableTextState` identity and focus across two keystrokes. |
| R3A-03 / R3B-04 (P1): after a card re-init the fade and the text disagree, because typed-but-unlogged values were never captured | §2: in LOG mode every keystroke records the edited set and every mirror target, checked or not, in ONE notifier write together with the fade change. Restored text, key and fade then always agree, and typed values stop being lost on scroll or leave + RESUME. |
| R3B-05 (P1): `TAP TO RE-OPEN` and the re-open semantics show when the button does nothing (review mode) | §1: the subline, `onTapHint` and `button` are derived from `onTap != null`. Card test A3. |
| R3B-06 (P2): accidental re-open has no feedback | Re-open focuses the card (the gold `LOG n SETS ✓` comes back, along with SWAP). The stronger FINISH line (R3B-02) is the guaranteed catch, and it is not optional. No new toast. |
| R3B-07 (P2): the dialog overflows with a long list | §3: `AlertDialog(scrollable: true)`. Names are capped at 3 plus `+N more` with `maxLines: 2` and an ellipsis. Test U-D3. |
| R3B-08 / R3A P3: the header and progress bar count warm-ups in the total; the dialog would not | §3: in LOG mode, header, progress bar and dialog all read `workingSetCounts`. OFF is unchanged. |
| R3B-09 (P2): `· PREFILLED` reads as a weight, and it labels sets mirrored from the user's own set 1 | Founder copy decision kept. Mirrored followers ARE app-filled, so the label is true. Risk noted for A12 (does it read right on a phone). |
| R3B-10 (P2): the TalkBack label is doubled and drops the subline | §1: `Semantics(button: onTap != null, label: subline == null ? label : '$label. $subline', onTapHint: reopen ? 'Re-open' : null, excludeSemantics: true)`. Semantics test SM1. |
| R3B-11 (P2): reps are app-filled but normal; bodyweight has no signal at all | Founder decision kept (reps are never faded). Stated in §5 and the train CLAUDE.md row. A bodyweight LOG is in A12. |
| R3A-07 / R3B-12 (P2): three-part keys versus the two-part cleanup code | §2 spells out each cleanup. The tests assert all three fields. |
| R3A-05 (P2): S1 cannot flip as written (no rebuild; Hive I/O; FINISH off-screen) | §6 S1: `put` inside `runAsync`, then `setElapsedSeconds(1)` to rebuild, and `scrollUntilVisible` to reach FINISH. |
| R3A-06 (P2): the mutations do not discriminate; protections are missing | §6: L1 runs at 2.0, the re-open probe is at 550 ms, the name-check mutation is dropped, and one mutation is listed per new protection. |
| R3B-13 (P2): an amber blame list for deliberate skips, and the "nothing logged" case | §3: calm `textDim` for skips, neutral wording, and `Nothing logged yet.` when zero working sets will be saved. |
| R3B-14 (P2): A12 misses new cases | §7 A12 extended. |
| R3A-08 (P2): §0 claimed artifacts that did not exist | This section is rewritten. The record is written now and committed with the batch. |
| R3B-17 (P3): the LOG guard (400 ms) is shorter than the superset reveal (200 ms delay `screen.dart:116` + 400 ms `ensureVisible` `:254`) | §1: after an advance that reveals a partner, the guard window is `kRevealGuard` (700 ms) for LOG too. |
| R3B-18 (P3): `clearSuggested` writes on every keystroke | No write when nothing changed (§2). |
| R3A P3: `isFaded` lacks `logMode`; `SetInputRow` has no faded input; import cycle; parity gate; non-empty mirror marks; one-frame flash; subline width | §2 signatures; `SetInputRow.fadedFields`; string field names in the provider; §8 parity re-baseline for every concept in an edited file; marks only for non-empty text; the flash is stated (§5); the subline gets 2 lines (§2 layout). |
| R3B-15/16/19/20 (P3): stale cite, coach snapshot, rollback caveats, mirror adoption | The cite is fixed (`screen.dart:116`, `:254`). The others are stated in §5 and §7. |

**Round 4** (R4A 0/1/3/6, R4B 0/1/6/8). Both reviewers found the same P1 independently, and the same main P2. Every finding was checked against the code (L17). Disposition:

| Finding | Resolution in revision 5 |
|---|---|
| R4A-01 / R4B-01 (P1): `excludeSemantics: true` without `onTap:` removes `SemanticsAction.tap`, so TalkBack cannot activate LOG or LOGGED (reviewer spikes: `hasAction(tap) == false`). The shipped UNDO toast has the same defect (`log_undo_toast.dart:84-88`). | §1: the Semantics node carries `onTap: onTap` and `enabled: onTap != null`. The same fix is applied to the UNDO button in this batch, since the flip exposes it. SM1 asserts `hasAction(SemanticsAction.tap)` on LOG, LOGGED, blocked and UNDO. |
| R4A-02 / R4B-02 (P2): the restore loop skips null captured fields (`exercise_card.dart:161-175`), so a cleared prefill comes back NORMAL after a re-init | §2: in LOG mode, when a capture exists, a null field restores as `''`. OFF is unchanged (the pre-seed capture runs in both modes, so the restore change is gated). Test P5b. |
| R4A-03 (P2): at 320 dp × 1.5/2.0 the card overflows at baseline on the `LAST: …KG × … REPS` Row (`exercise_card.dart:1002`), in both modes | §2 layout: that `Text` gets `Flexible` + `maxLines: 1` + ellipsis (layout only, both modes). L1 runs with an empty `lastPerformanceProvider` (prefill from `exercise.weight`). The new L2 runs with history. L1 proves height behaviour, not pixel width (Ahem font). |
| R4A-04 (P2): the "one predicate" guarantee was presence-pinned only, and the scan range was unstated | §3: one helper, `saveableSetIndexes(exIdx)` (the `maxSetLog` extension + `wouldSaveSet`). `completeWorkout`, `workingSetCounts` and `finishGuard` all iterate it. Behavioural parity test U-D1b runs the real `completeWorkout` and compares the saved rows with `finishGuard`. |
| R4B-03 (P2): an accidental "did it register?" second tap on the last exercise at 0.8-2 s re-opens it | §1: RE-OPEN is ignored within `kReopenGuard` = 1200 ms after an advancing LOG. Probe R1 at 1000 ms. |
| R4B-04 (P2): COMPLETE with zero saved sets still marks the day completed and counts toward streak and badges (pre-existing, `train_provider.dart:2045-2076`) | §3: copy `Nothing logged yet. Completing now saves no sets.` §5 states it. An OI is minted for the credit question (founder decision, COMPLETE stays enabled). Ledger `ZERO-SET-COMPLETION` (`blocked_on_user`). |
| R4B-05 (P2): the existing duration Row overflows the dialog at 320 dp / large font (fixed 56 px boxes, `finish_dialog.dart:46-122`) | §3: the Row becomes a `Wrap` (shared with OFF; it only differs when it would overflow). U-D5 covers OFF. |
| R4B-06 / R4A-07 (P2/P3): `workingSetCounts` total = 0 (all sets warm-up) gives NaN; `NaN.round()` throws at `screen.dart:322` | §3: the percent is a pure `workingProgress` that returns 0.0 when total = 0. Pure test. |
| R4B-07 (P2): `· PREFILLED` labels a user's own typed set 1 via the mirrored followers, and it is on for nearly every card | §2: the subline says PREFILLED only while the mirror SOURCE's weight is still app-filled. Typing set 1 switches it to `KG LIFTED`. The fade on followers stays. The copy is unchanged (founder). |
| R4A-05, R4A-06 (P3): the second-tap re-select needs a pause between taps; `onTapHint` surfaces as a custom action, not `hint` | P3 pumps 600 ms between taps. SM1 reads `customSemanticsActionIds`. |
| R4A-07 (P3): `scrollable: true` changes the OFF dialog | `scrollable: logMode`. |
| R4A-08 (P3): the "no write when nothing changes" check is vacuous (`SetInputValues` has no `==`) | `recordCardEdit` compares field by field (a private `_sameValues`). `SetInputValues` is untouched. |
| R4A-09 / R4B-09 (P3): an all-warm-up "done" exercise is labelled "Not logged"; name-keyed `reopenedExercises`; marks on hidden fields | Cause-agnostic wording `Nothing to save for: …`; names capped at 5. The name-key edge is stated (OI-358 already crashes on duplicate names). First-init marks only fields in `mirrorFieldsFor(loggingType)`. |
| R4A-10 (P3): the review-mode test becomes `null == null`; R3/A4 lack mutations; screen wiring is unpinned | The review-mode test seeds `setInputValues`. Mutations are listed for R3 and A4. Source pins S2 cover the toast-clear condition and `_focusExercise` in `_onReopenExercise`. |
| R4B-08 (P3): after RE-OPEN the 400 ms stamp is shorter than `_focusExercise`'s 60 + 400 ms scroll | The re-open stamps the `kRevealGuard` (700 ms) window. R2 probes at 500 ms. |
| R4B-10 (P3): the LOGGED label reads "TAP" to TalkBack; fields have no spoken label | The logged label is `Logged` (no subline) + hint `Re-open`. The always-present field wrapper also carries `label:` (KG/REPS/MIN/KM). |
| R4B-11 (P3): `logSets` is not guarded by `_completing` | `logSets` returns while `_completing`. Notifier test + mutation. |
| R4B-12/13/14/15 (P3): typing latency; followers stop following after a re-init; A12 gaps; web auto-deploys `main` (`vercel.json` `ignoreCommand`); no closure entry for reps/bodyweight | A12 items added. Stated in §5. §7 exposure rewritten with the `vercel.json` evidence. Ledger `REPS-BODYWEIGHT-SIGNAL` (`verified_clean`, founder decision 2026-10-18). |

**Round 5** (R5A 0/0/2/7, R5B 0/0/5/5). No P0 or P1 from either reviewer. Reviewer spikes confirmed:
- one tap action with no double-fire;
- the restore change breaks no seeding;
- the `completeWorkout` extraction is identical, and U-D1b is buildable (spike: real awaited `completeWorkout` wrote `exlog_*` rows A=3 and D=3 of 4; B and C were not saved);
- select-all on tap and `EditableTextState` identity.

Disposition:

| Finding | Resolution in revision 6 |
|---|---|
| R5A-01 (P2): U-D1b's helper mutation cannot redden a relative-parity check | U-D1b asserts absolute counts (exercise `sets: '3'` + checked key `3-3` -> exactly 4 saved sets; A=3, D=3; B, C absent). |
| R5A-02 (P2): protections without a mutation | §6 now lists a mutation (or `presence only` + reason) for U-D2, U-D4, U-D5, `capNames`, P6, `scrollable`, the screen `workingProgress` wiring, and the one-`copyWith` rule. R2b is dropped (R2 already reddens). |
| R5B-01 (P2): `maxLines: 2` truncates the names the guard line exists to show | The guard lines have no `maxLines` (the dialog scrolls in LOG mode; `capNames` still caps at 5). U-D3 asserts the first name is visible at 320 dp × 2.0. |
| R5B-02 (P2): TalkBack gets no confirmation that LOG or RE-OPEN worked | The toast text sits in `Semantics(liveRegion: true, container: true)`. On `reopened` the screen calls `SemanticsService.sendAnnouncement(View.of(context), '{name} re-opened', …)` (Flutter 3.41 `semantics_service.dart:81`; `announce` is deprecated). SM2 uses `tester.takeAnnouncements()`. |
| R5B-03 / R5A-05 (P2/P3): unit labels would say MIN on a SEC field; a blank field reads the unit twice | The field's Semantics `label` is the same string `_compactInput` already receives as its hint (`set_input_row.dart:163,168,189`; one source). It is null while the controller is empty, because the `hintText` already speaks it. SM1 covers a timed card (`SEC`) and runs `tester.ensureSemantics()`. |
| R5B-04 (P2): after a card re-init the followers stop following, which is the RE-OPEN amend path | §2 adds a LOG-mode re-seed after the restore loop. For each mirror field, `_mirrored[field][t] = text` for every set `t` after the source whose key is suggested and whose text equals the source's text, but ONLY while the source's own key is NOT suggested (the user typed set 1). History prefill stays non-following, as in batch 2. Test P9. |
| R5B-05 (P2): typed-but-unlogged reads like a deliberate skip | `finishGuard.typedUnsaved`: 0 saved sets and at least one rendered (`mirrorFieldsFor`) field with a non-null captured value and NO suggested key (the user typed it). It gets a `warn` line `Typed, not logged. Not saved: {names}`. Bodyweight (reps only) cannot be told apart and stays in the skipped line (stated). |
| R5B-06 / R5A-04 (P3): `Wrap(spacing: 6)` adds about 24 px and wraps OFF on common phones | `spacing: 0` (the existing `:` padding and `SizedBox(8)` give the gaps), `runSpacing: 6`. U-D5 asserts one line at 360 dp × 1.0 in OFF. |
| R5B-07 (P3): "Suggested value" collides with the gold TRY suggestion | The hint is `Prefilled value` (`WardroomCopy.activePrefilledHint`). |
| R5B-08 (P3): a LOG about 0.5 s after an accidental re-open is a silent dead tap | Kept, since the 700 ms window covers the 460 ms focus scroll. A12 item. |
| R5B-09 (P3): web rollback | §7: Vercel "promote previous deployment" is the fast web rollback; A12 gets a web smoke right after the deploy. |
| R5B-10 (P3): ledger wording; the celebratory completion screen after "saves no sets" | `REPS-BODYWEIGHT-SIGNAL` evidence reads "accepted founder decision 2026-10-18". The zero-set OI body names `completion_sheet.dart:41-49` copy as part of the decision. |
| R5A-03 (P3): S1 copy stale | `Nothing to save for: <name>`. |
| R5A-06 (P3): the screen needs Fraunces primed; the card harness cannot prefill weight | Test setup primes `AppTypography.numeric` in `renderFontsFirst`. `card_harness.dart` `exercise()` gains a `weight` parameter. |
| R5A-07 (P3): (c) marks hidden fields; the "never lost" claim is overstated | (c) marks only `mirrorFieldsFor` fields. §2/§5: unparseable partials (`.`) and cardio decimal minutes (`int.tryParse('12.5')` is null) are not kept across a re-init. This is no regression (lost before too); A12 covers it. |
| R5A-08 (P3): the registry says `logSets` is deliberately unguarded; `_completing` is not reset on a throw; cites | §8 rewrites that registry sentence. §5 states that a throwing `completeWorkout` leaves LOG and UNDO dead until the screen is left (as UNDO today). Cites: caller `exercise_card.dart:1090`, route `app_router.dart:381`. |
| R5A-09 (P3): live-state evaluation, the PR-detection loop, progress over 100% | §3: `saveableSetIndexes` is evaluated on the live `state` per exercise, in the same synchronous block as the `vals!` reads. The PR-detection loop (`train_provider.dart:1914-1951`) keeps its own scan (stated). `workingProgress` clamps to `0..1`. |

**Round 6** (delta review of revision 6, both lenses: 0 P0, 0 P1, 2 P2, 6 P3; verdict "converged after R6-01 and R6-02 are folded in as plan text"). Spikes confirmed that `sendAnnouncement` and `takeAnnouncements` exist, that a `label`/`hint` toggle keeps `EditableText` identity, that the unit strings are KG/REPS/SEC/MIN/KM, and that the re-seed can be built at init time.

| Finding | Resolution in revision 7 |
|---|---|
| R6-01 (P2): U-D5's `spacing: 6` mutation does not redden at 360 dp, because the Row already overflows under the test font | U-D5 runs at 390 dp and asserts that the `MIN : SEC` label's top equals the fields' top (`spacing: 0` passes, `spacing: 6` wraps). The fit at 360 dp with real fonts goes into A12. |
| R6-02 (P2): the text-equality clause of the re-seed is unprotected | P9c: a returning user types 62.5 in set 1, the card is re-pumped, and set 1 is edited to 65; sets 2-3 stay 60. Mutations: drop the text-equality clause; drop the source-not-suggested gate. |
| R6-03 (P3): `typedUnsaved` mislabels a LOGGED all-warm-up exercise | The typed field must sit on an UNCHECKED set. Pure case added. |
| R6-04 (P3): the `sendAnnouncement` Future trips `unawaited_futures: warning` | `unawaited(SemanticsService.sendAnnouncement(...))`. |
| R6-05 (P3): mutations for the field label and hint; `typedUnsaved` scanning reps; naming list | SM1 mutations: drop `label:`; hard-code `'KG'`; make `hint` unconditional. Pure mutation: `typedUnsaved` scans reps (the fixture includes captured reps). §8 naming adds `typedUnsaved`, `reopenedUnsaved`, `capNames`, `workingSetCounts`, `FinishGuard`. |
| R6-06 (P3): the U-D1b fixture wording | A fifth exercise E (`sets: '3'`) with checked key `4-3` created via `toggleSet` (`train_provider.dart:1508-1517`, which is unbounded) plus `recordSetValues`. |
| R6-07 (P3): two edge cases where the re-seed differs from in-card mirroring | Stated in §5. |
| R6-08 (P3): the live region re-announces while a logged set is edited inside the 5 s toast | A12 note. |

Out of scope, suggested as a separate task: `body_measurements_sheet.dart` has the same `excludeSemantics`-without-`onTap` defect (R5B-07 side note).

**Founder, 2026-10-20 (after round 6):** "Accept both" (the batch-1/2 B-pass reviews), "fold OI-361 into flip batch", "go ahead". OI-361: a workout with zero logged sets must not complete. That replaces the R4B-04 resolution (COMPLETE stays enabled with a warning) with U-E below, on BOTH flag paths.

**Round 7** (delta review of U-E, revision 8: 0 P0, 0 P1, 3 P2, 3 P3; verdict "sound in design; fold the three P2s in and U-E is converged"). Spikes: a real awaited `completeWorkout` through `setUpHiveForTests` left no Hive keys and `total_workouts_done` null for zero sets and warm-up-only, and completed fully with one saveable set; `fa.periodicTimerCount` reads 1 before and 1 after a guarded `completeWorkout` that followed a real `startWorkout`.

| Finding | Resolution in revision 9 |
|---|---|
| R7-01 (P2): the OFF blocked dialog keeps `scrollable: false`, so at 320 dp, a large font and the keyboard up the block line can overflow; nothing tests it | `AlertDialog(scrollable: logMode \|\| blocked)`. OFF stays non-scrolling when not blocked (U-D5). U-E2 adds 320 dp × textScale 2.0 with a keyboard inset. Mutation: `scrollable: logMode`. |
| R7-02 (P2): "the coach path always has a set" holds for `_maybeCompleteScheduledDay` and the tap card, NOT for `submitWorkoutDraft` (`conversational_log_handler.dart`), which calls `markCompleted` even when every exercise yielded no set; `WorkoutLogConfirmCard` only checks `draft == null` | Closed in this batch (§3b). One predicate `draftHasLoggableSet` over the extracted `draftExerciseSets` (the loop's own set builder). `submitWorkoutDraft` returns before any write when it is false and keeps the draft; the card disables CONFIRM and says `No sets to log. Tell the coach your sets, or discard.` Tests U-E4/U-E5. |
| R7-03 (P2): U-E1's timer assertion cannot be built (the timer reads `DateTime.now()`, which fakeAsync does not fake), and the guard's placement before the timer cancel has no mutation | U-E1 calls the real `startWorkout` inside `fakeAsync` and asserts `periodicTimerCount` is 1 before and after. Three mutations: the guard moved below `_timer?.cancel()`; the guard without `!state.isSaved`; `hasSaveableSet` constant false. |
| R7-04 (P3): the block hides the re-opened / typed lines, and "Nothing logged yet" is untrue for an all-warm-up session | The re-opened and typed lines stay under the block line; the skip and partial lists are dropped while blocked. Copy: `No working sets logged (warm-ups don't count). Log one to complete, or cancel the workout.` |
| R7-05 (P3): the notifier guard is dead behind the modal dialog, but if it fired after COMPLETE, the closure would already have cleared the coach snapshot and the UNDO toast; the review-mode dialog is unreachable (FINISH is disabled when `isSaved`) | The COMPLETE closure re-reads the live state first and returns before any side effect (U-E2b: the state loses its last saveable set while the dialog is open). The `isSaved` clause is behaviour preservation, not a user-visible state (§3b). |
| R7-06 (P3): U-E3 misses two mutations | Cases: only the second exercise is saveable; a checked key beyond `e.sets`. |

Founder decisions on record (chat, 2026-10-20):
- device check after merge;
- OFF path kept as kill switch, with its removal tracked by a minted OI;
- RE-OPEN (the founder's "amend log");
- faded prefill, no alert;
- one batch;
- FINISH lists unsaved;
- faded vs normal;
- `{kg} KG · PREFILLED`.

## 1. U-A RE-OPEN (founder: "amend log")

**Today:**
- A done exercise's LOG row is `_LogExerciseButton(label: 'LOGGED ✓', style: logged)` with no `onTap` (`exercise_card.dart:773-777`), and the widget disables any logged button (`:1274`).
- Values of logged sets are editable (captured per keystroke).
- `−`/`+` work on logged sets.
- Post-workout, receipt -> Edit opens `EditWorkoutLogSheet` (values only).

**Change:**
- **Button (`_LogExerciseButton`):**
  - `enabled = onTap != null` (drops `&& !logged`).
  - The logged style keeps its look. ONLY when `onTap != null` it shows the subline `TAP TO RE-OPEN` (`WardroomCopy.activeReopenSubline`).
  - Semantics: `Semantics(button: true, enabled: onTap != null, onTap: onTap, label: …, onTapHint: style == logged && onTap != null ? WardroomCopy.activeReopenHint : null, excludeSemantics: true)` (R4A-01: without `onTap:` the excluded GestureDetector's tap action is lost).
    - The ready and blocked labels are `subline == null ? label : '$label. $subline'`.
    - The logged label is `Logged` (`WardroomCopy.activeLoggedSemantics`), with no subline; `'LOGGED ✓'` stays the visual text.
  - The UNDO button in `LogUndoToast` (`log_undo_toast.dart:84-88`, shipped in batch 2) gets the same `onTap: onUndo` on its Semantics.
  - The `activeLoggedLabel` comment "Disabled LOG area" is updated.
- **Card:** in LOG mode and not review mode (`!data.isSaved`), the logged button's `onTap` calls a new `onReopenExercise` callback (beside `onLogExercise`). In review mode `onTap` stays null, so there is no subline and no hint.
- **Provider:**
  - `logSets` returns while `_completing` (R4B-11; `unlogSets` already does).
  - `unlogSets(..., {required String exerciseName, bool reopened = false})`. On success with `reopened`, it adds `exerciseName` to the new `ActiveWorkoutData.reopenedExercises: Set<String>`. This happens in the same `copyWith` as the uncheck (one state change).
  - The set is never removed during a session. Its reader filters it (§3).
  - `startWorkout`/`cancelWorkout` reset it (constructor default); `copyWith` threads it.
  - UNDO keeps calling `unlogSets` without `reopened`.
- **Controller (`LogExerciseController.reopen({exerciseIndex, readState, unlogSets})`):**
  - It is ignored while `shouldIgnoreLog(now, lastAdvanceAt, window: kReopenGuard)` holds (`kReopenGuard = 1200 ms`, R4B-03: covers a "did it register?" second tap on the last exercise).
  - It returns `noop` when the exercise is not done (`!isExerciseDone`).
  - Otherwise it reads fresh state, collects the checked sets of the exercise, and calls `unlogSets(exIdx, sets, exerciseName: <name read from that fresh state>, reopened: true)`.
  - On `true` it stamps `_lastAdvanceAt = now` and `_lastAdvanceWindow = kRevealGuard` (`kRevealGuard = 700 ms`; `_focusExercise` scrolls 60 + 400 ms, `screen.dart:241,254`), and returns `LogOutcomeKind.reopened` (new enum member). Otherwise it returns `noop`.
- **Superset reveal guard (R3B-17):** `log` stamps `_lastAdvanceWindow = revealPartner != null ? kRevealGuard : kLogInputGuard`, and its own check uses `_lastAdvanceWindow`. A LOG tap during the reveal scroll is ignored.
- **Screen:**
  - `_onReopenExercise(exIdx)` is declared AFTER `_onLogExercise` (keeps the `indexOf` slices at `active_workout_set_logging_behavioral_test.dart:420-486`).
  - On `reopened` it clears the UNDO toast only if `record.exerciseIndex == exIdx`, and calls `_focusExercise(exIdx)`.
  - It also announces `WardroomCopy.activeReopenedAnnouncement` (`'{name} re-opened'`) via `unawaited(SemanticsService.sendAnnouncement(View.of(context), …, TextDirection.ltr))` (R5B-02; `unawaited` for `unawaited_futures: warning`, R6-04).
  - `LogUndoToast`'s text is wrapped in `Semantics(liveRegion: true, container: true)`, so TalkBack reads the LOG toast.
- **After re-open:**
  - ✓ DONE becomes ⇄ SWAP (derived per build), and FINISH goes back to outline.
  - The coach snapshot stays as LOG wrote it (same as UNDO; §5).
  - Mirror followers keep their logged values and follow the next set-1 change.
  - `setInputValues`, `warmUpSets` and `suggestedInputs` are untouched, so untouched app-filled fields fade again (§2).

## 2. U-B Faded prefill + subline (no alert)

**State (provider):** `ActiveWorkoutData.suggestedInputs: Set<String>`, keys `'$exIdx-$setIdx-$field'`, where `field` is the string `weight|duration|distance`. `train_provider.dart` uses strings, not `SetField`: `log_exercise_logic.dart` imports the provider (import cycle). Reps are never suggested (founder 2026-10-18). A field is suggested while its text was put there by the app and the user has not typed in it.

**One writer per card event:** `ActiveWorkoutNotifier.recordCardEdit(int exIdx, {Map<int, SetInputValues> values = const {}, Set<String> mark = const {}, Set<String> clear = const {}})`.
- It applies the value captures and the key changes in ONE `copyWith`.
- It returns without writing when `isSaved`, or when nothing would change (R3B-18). Values are compared field by field with a private `_sameValues`, since `SetInputValues` has no `==` (R4A-08).

Callers (card only, LOG mode only):
- **(a) First init.** In the existing post-frame pre-seed callback (`exercise_card.dart:185-191`, never during build), the captures of that callback move into `recordCardEdit`. The callback marks every non-empty prefilled field in `mirrorFieldsFor(loggingType)` (rendered fields only, R4A-09), but only for sets that had no captured value at `initState` (first init). The prefill comes from history (`lastWeight × effectiveLoadFactor`) or the prescribed weight (`:129-139`).
- **(b) A keystroke** in field `f` of set `s` (`_onFieldChanged`, which now receives the field):
  - captures set `s`. A checked set keeps the valid-only rule (`:396`). An unchecked set records its raw parsed text, so a cleared field restores blank;
  - clears key `s-f`;
  - for every mirror target `t` written: captures `t`, marks `t-f` when the copied text is non-empty, and clears it when the text is empty.
- **(c) `_seedAppendedSets`** (`:338-382`, post-frame like its capture): marks each non-empty seeded field in `mirrorFieldsFor(loggingType)`.

Consequence: `setInputValues` now holds the live text of every set in LOG mode.
- `completeWorkout` and `liveVolumeKg` read only checked sets (`train_provider.dart:2010`, `:1380-1389`), so nothing new is saved or counted.
- Typed-but-unlogged values now survive a card re-init (scroll away, leave + RESUME). Exceptions: text the capture cannot parse is not kept, such as a partial `.` or cardio decimal minutes (`int.tryParse('12.5')` is null). Those were lost before too.
- **Restore (R4A-02):** in LOG mode, when a captured record exists for a set, `_initControllers` (`exercise_card.dart:158-176`) restores a null field as `''`, so a cleared prefill stays cleared. OFF keeps today's skip-null loop.
- **Mirror re-seed (R5B-04):** in LOG mode, after the restore loop and `_baselineMirrorSource`, for each field in `mirrorFieldsFor`, while the source's own key is NOT suggested (the user typed set 1): `_mirrored[field][t] = text` for every set `t` after the source whose key is suggested and whose text equals the source's text. Followers created by the mirror keep following after a re-init. History prefill (source still suggested) stays non-following, as in batch 2.
- OFF mode is unchanged (`_onFieldChanged` returns on `!_logMode`).

**Cleanup:**
- `startWorkout`/`cancelWorkout` reset (constructor default).
- `swapExercise` removes keys starting with `'$ex-'`.
- `removeExercise` re-indexes with a 3-part split, `[e, s, f]` -> `'${e-1}-$s-$f'` for `e > ex`, and drops `e == ex`.
- `removeLastSet` removes every key starting with `'$ex-$last-'`.
- `copyWith` threads the field, so the 1 s timer cannot drop it.

**Render rule:** pure `isFaded({required bool logMode, required ActiveWorkoutData data, required int exIdx, required int setIdx, required String field})`. It is true iff all of these hold:
- `logMode`;
- `!data.isSaved`;
- the key is in `suggestedInputs`;
- the set is not checked.

So logged sets are never faded, and after RE-OPEN or UNDO the untouched app-filled fields fade again.

**`SetInputRow`** gains `final Set<SetField> fadedFields` (default empty) and `onChanged: ValueChanged<SetField>?` (one caller, `exercise_card.dart:1090`; OFF passes `null`). Every field is built as `Semantics(label: controller.text.isEmpty ? null : <the hint string _compactInput already receives: KG/REPS/SEC/MIN/KM>, hint: faded ? WardroomCopy.activePrefilledHint : null, child: SizedBox(height: 38, child: TextField(...)))` (R4B-10, R5B-03).
- The unit comes from one source (`set_input_row.dart:163,168,189`).
- It is null on a blank field, because the `hintText` is then already spoken.
- `WardroomCopy.activePrefilledHint` is `Prefilled value` (R5B-07). That wrapper is ALWAYS present, in both modes, so the tree shape is constant.

| | Text style | `TextField.onTap` |
|---|---|---|
| Faded | `AppColors.textPrimary.withValues(alpha: 0.62)` | `() => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length)` |
| Normal | `AppColors.textPrimary` (unchanged) | `null` |

`onTap` is a property, not a wrapper. A second tap before typing re-selects all (still faded).

The "Tap to edit values" header hint (`exercise_card.dart:941`) is hidden in LOG mode.

**Subline:**
- Loaded types keep `{kg} KG LIFTED` (`liftedSubline`), unless the mirror SOURCE set's weight is still suggested (R4B-07). Then the subline is `{kg} KG · PREFILLED` (new pure `prefilledSubline`, `WardroomCopy.activePrefilledSublineTemplate`). So a returning user's untouched card says PREFILLED, and a user who typed set 1 sees `KG LIFTED` while the mirrored followers stay faded.
- Non-loaded types: no subline (unchanged).
- Faded values COUNT on LOG and in the volume (unchanged).

**Layout:** `_LogExerciseButton` uses `constraints: BoxConstraints(minHeight: 44)` instead of `height: 44`. The label is `maxLines: 1` inside `FittedBox(fit: BoxFit.scaleDown)`. The subline is `maxLines: 2`, centred, with no FittedBox, so `{kg} KG · PREFILLED` (about 130 px at 9 px on a 134 px button at 320 dp) wraps instead of shrinking to 6 px.

The pre-existing `LAST: …KG × … REPS` Row (`exercise_card.dart:1002`) overflows at 320 dp × 1.5 in both modes (R4A-03). Its `Text` gets `Flexible` + `maxLines: 1` + `TextOverflow.ellipsis` (layout only).

## 3. U-D FINISH guard and working-set counts (LOG mode)

**One predicate (R3A-02, R3B-01):**
- `ActiveWorkoutData.wouldSaveSet(int ex, int s)` = checked AND not warm-up AND `setInputValues['$ex-$s'] != null`. This is exactly the three `continue`s at `train_provider.dart:2010-2013`.
- `ActiveWorkoutData.saveableSetIndexes(int ex)` returns the set indexes `completeWorkout` will save: it scans `0 ≤ s < maxSetLog` (the template count extended by checked keys, `train_provider.dart:1993-2000`, moved into the helper) and keeps `wouldSaveSet`.
- `completeWorkout` iterates `saveableSetIndexes(exIdx)` (`final vals = state.setInputValues['$exIdx-$s']!;`). The helper is evaluated on the live `state` per exercise, in the same synchronous block as the `vals!` reads, never on a `data` captured before an `await` (R5A-09). The PR-detection loop (`train_provider.dart:1914-1951`) keeps its own `maxSet` scan; it is not a save path. `workingSetCounts` and `finishGuard` iterate the same helper (R4A-04). The dialog and the save cannot drift.
- A behavioural parity test runs the real `completeWorkout` and compares (§6 U-D1b).

Pure readers in `log_exercise_logic.dart`:
- **`workingSetCounts(data) -> (saved, total)`.** `saved` = Σ `saveableSetIndexes(ex).length`. `total` = Σ `int.tryParse(e.sets) ?? 3` minus warm-up keys within range.
- **`workingProgress(counts) -> double`**: `total == 0 ? 0.0 : (saved / total).clamp(0.0, 1.0)` (R4B-06: `NaN.round()` throws at `screen.dart:322`; R5A-09: a checked key beyond `e.sets` would exceed 100%).
- **`finishGuard(data) -> FinishGuard`.** Over the exercises present now, it returns:
  - `reopenedUnsaved`: names in `reopenedExercises` with 0 saved sets;
  - `typedUnsaved`: other names with 0 saved sets where at least one UNCHECKED set has a `mirrorFieldsFor` field with a non-null captured value and no suggested key (the user typed it, R5B-05; unchecked so a LOGGED all-warm-up exercise is not called typed, R6-03);
  - `skipped`: the remaining names with 0 saved sets;
  - `partial`: `(name, saved, working)` for exercises with ≥1 saved and saved < working (`+` after LOG).

**Dialog** (`_showFinishDialog` gains `bool logMode`; one caller, `screen.dart:625`): `AlertDialog(scrollable: logMode || blocked)` (R7-01). The duration `Row` (`finish_dialog.dart:46-122`, fixed 56 px boxes) becomes a `Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 0, runSpacing: 6)` in both modes. The existing `:` padding and `SizedBox(8)` give the gaps, so it lays out like the Row until the Row would overflow (R4B-05, R5B-06). In LOG mode:

| Line | Copy | Colour |
|---|---|---|
| Count | `{saved}/{total} sets logged` from `workingSetCounts` | `textDim` |
| Nothing saved | when `saved == 0` (and not review mode): U-E's `No working sets logged (warm-ups don't count). Log one to complete, or cancel the workout.` (`WardroomCopy.activeFinishZeroSetBlocked`); the re-opened and typed lines stay under it, the skipped and partial lists are dropped (R7-04); COMPLETE disabled | `warn` |
| Re-opened | `Re-opened, not logged again. Not saved: {names}` (`activeFinishReopenedTemplate`) | `warn` |
| Typed | `Typed, not logged. Not saved: {names}` (`activeFinishTypedTemplate`) | `warn` |
| Skipped | `Nothing to save for: {names}` (`activeFinishSkippedTemplate`; cause-agnostic, true for an all-warm-up exercise too) | `textDim` |
| Partial | `Partly logged: {name} {saved}/{working}` (`activeFinishPartialTemplate`) | `textDim` |

- Names are joined with `, ` and capped at 5 plus ` +N more` (pure `capNames`).
- The guard lines have no `maxLines`: the dialog scrolls in LOG mode, and `capNames` caps the length (R5B-01).
- COMPLETE stays enabled while at least one set will be saved: skipping an exercise is legitimate. With zero, U-E blocks it.

## 3b. U-E Zero-set block (OI-361; both flag paths)

**Today:** COMPLETE with nothing saveable still runs `markCompleted` (`train_provider.dart:2068`), `total_workouts_done + 1` (`:2076`), the daily and weekly streaks (`:2089`, `:2117`) and `BadgeService.checkAll` (`:2170`). The completion sheet then shows `Workout Complete!` / `0 SETS LOGGED` (`completion_sheet.dart:40`).

**Change:**
- **Predicate:** `ActiveWorkoutData.hasSaveableSet` = any exercise with a non-empty `saveableSetIndexes` (§3). It is the same predicate the save uses, so it is exactly "completeWorkout would write no exercise".
- **Notifier guard (defence in depth):** the first line of `completeWorkout` is `if (!state.isSaved && !state.hasSaveableSet) return;`. It sits before the timer cancel, so the session is left exactly as it was: no `markCompleted`, no counters, no streak, no badges, no `isComplete`, `_completing` untouched. Review mode (`isSaved`) keeps today's path.
- **Dialog, both modes** (`_showFinishDialog`): when `!data.isSaved && !data.hasSaveableSet`:
  - COMPLETE is disabled (`onPressed: null`, label in `textMute`). Its `TextButton` semantics report it disabled.
  - A `warn` line reads `No working sets logged (warm-ups don't count). Log one to complete, or cancel the workout.` (`WardroomCopy.activeFinishZeroSetBlocked`; R7-04 names warm-ups because an all-warm-up session reads `0/N`).
    - In LOG mode it replaces U-D's `Nothing logged yet. Completing now saves no sets.` row; that copy and `activeFinishNothingLogged` are dropped. The re-opened and typed lines stay under it (R7-04).
    - In OFF mode it is added under the count line, and the dialog scrolls while blocked (R7-01).
  - The COMPLETE closure re-reads the live state and returns before any side effect when it has no saveable set (R7-05). `blocked` is a snapshot from when the dialog opened; the re-check keeps the coach snapshot, the UNDO toast and the elapsed time intact if the state changed underneath.
  - CONTINUE stays. Cancel stays on the screen (`screen.dart:637`, `_showCancelDialog`); no new discard button.
- **The OFF path changes** (founder: "zero sets logged should not be allowed", not LOG-only). It is listed in §7 "Code shared by both paths".
- **Review mode:** FINISH is `✓ ALREADY SAVED` and disabled when `isSaved` (`screen.dart:647-652`), so the dialog never opens there. The `isSaved` clause in the guard and the dialog is behaviour preservation, not a user-visible state (R7-05).
- **The coach paths** (R7-02, verified by reading):
  - `tool_dispatcher._maybeCompleteScheduledDay` auto-completes only when `plannedCount > 0` and every planned exercise is logged, so it has a set. The tap card (`completeWorkoutFromPrompt`) exists only after a coach `logSet` that date. Both untouched.
  - `submitWorkoutDraft` (`conversational_log_handler.dart`) skipped exercises with no sets but then called `markCompleted` unconditionally. A chat draft with no sets therefore flipped `schedule_*` to completed and wrote `wlog_*` (the same zero-set credit class; it does not bump `total_workouts_done`). Fix: the set builder is extracted as `draftExerciseSets(exercise)`, and `draftHasLoggableSet(draft)` = any exercise with a non-empty `draftExerciseSets`. `submitWorkoutDraft` returns before any write when it is false and keeps the draft. `WorkoutLogConfirmCard` disables CONFIRM on the same predicate (faded slab, `onTap: null`) and shows `No sets to log. Tell the coach your sets, or discard.` (`WardroomCopy.coachDraftNoSets`, `warn`). DISCARD stays.

**Header and progress bar (R3B-08):** in LOG mode `screen.dart:322,335,338` pass `workingSetCounts` to `_buildHeader` (new optional `counts` param), and `workingProgress` to the bar and the percentage. In OFF they keep `completedSets/totalSets` and `progressPercent`.

## 4. U-C The flip

**Writer:** `dev_panel_screen.dart:269-275` (debug only: `/dev` under `kDebugMode`, `app_router.dart:381`).

**Readers:**
- `screen.dart:325`. It is read once per build and decides `onLogExercise`, `onReopenExercise`, the toast host, `allLogged`, the FINISH variant, the header counts and the U-D dialog.
- The dev panel (`:270`, `:496-497`, `:520-523`).

**Getter:** `final stored = configBox.get(key); return stored is bool ? stored : true;` inside the `try`; the `catch` returns `false`.

| Stored value | Result |
|---|---|
| absent or non-bool | ON |
| `false` | killed |
| box not open | OFF |

The dev panel row and toast read `ON`/`KILLED`, and the comment at `:267` is updated.

## 5. What every user of the next build sees (known effects, stated)

The next build has the LOG flow, UNDO and mirror (shipped), plus RE-OPEN, the fade and the FINISH guard. Known effects:

**Session lifetime:**
- Session state is in-memory (`train_provider.dart:1407-1423`). `active_session` is only the coach snapshot (`active_workout_persistence.dart:3-37`).
- Killing the app or reloading the web page loses the workout, before and after this change. Leave + RESUME keeps it, now including typed-but-unlogged values and the fade (§2).

**Prefill and fade:**
- Returning users' prefill is last session's FIRST set for every set (`train_provider.dart:91-94`). Per-set last values stay in OI-357.
- Faded means app-filled weight, duration or distance.
- Reps are app-filled and always normal (founder 2026-10-18). A bodyweight exercise therefore shows no fade and no subline: `LOG 3 SETS ✓` logs the prefilled reps (A12).
- The fade appears one frame after a card is first built (the marks are written post-frame). A typed value equal to a mirrored follower re-adopts the follower (`mirrorTargets`), so a later set-1 edit overwrites and re-fades it.
- On web, every field also selects all on keyboard focus (the `EditableText` default for web/desktop). On a tap, the faded `onTap` rule is the same on all platforms.

**RE-OPEN, guards and snapshot:**
- After RE-OPEN the coach snapshot still shows the LOG state until the next LOG (as UNDO; ≤ 2 h staleness rule).
- A RE-OPEN tap during a running save returns `noop` silently (the save is milliseconds long).
- If `completeWorkout` throws, `_completing` stays set, so LOG, RE-OPEN and UNDO are dead until the screen is left (as UNDO today).
- A LOG tap within 700 ms after a re-open is ignored (it covers the 460 ms focus scroll).
- A bodyweight exercise that was typed but not logged lands in the calm `Nothing to save for` line: reps are never marked, so typed and untouched cannot be told apart.
- After a card re-init, followers created by the mirror follow again (§2 re-seed). Followers of a history prefill still do not follow (batch 2). Two rare differences from in-card mirroring (R6-07):
  - a returning user who typed exactly the history value into set 1 gets following followers after a re-init;
  - after a warm-up moved the source, a pending follower whose text differs from the new source stops following after a re-init.
- RE-OPEN is keyed by exercise name. A swap back to the same name inherits the mark; duplicate names already crash the screen (OI-358).
- COMPLETE with zero saveable sets is blocked on both paths (U-E, OI-361). A user who wants out uses Cancel (all progress is discarded, as today).
- A chat workout card whose draft has no sets cannot be confirmed (R7-02); DISCARD stays.
- The `isSaved` exception in the guard keeps today's review-mode path; no user reaches it through the dialog (FINISH is disabled in review mode, R7-05).
- Every keystroke in LOG mode is one provider write and one screen rebuild (checked sets already did this). Typing latency on a low-end phone is in A12.

**Supersets and pre-existing issues:**
- Supersets have their own LOG per exercise (D2).
- Pre-existing on both paths: OI-358, OI-352 (hidden by LOG), OI-353, decimal cardio minutes `Fix time` (R1B-12).

## 6. Tests (rule 21; each mutation confirmed applied with `grep -c`; compile errors are not proof; the failing test names are recorded in the ledger)

**Flag** (`test/features/train/log_exercise/log_exercise_flags_test.dart`):
- F0 (FIRST test, no Hive): OFF.
- F1 absent: ON.
- F2 `false`: OFF; `true`: ON.
- F3 `'false'`, `0`, `'off'`: ON.
- F3b delete: ON.
- Mutations: `: true` -> `: false` (F1); catch `false` -> `true` (F0); `stored is bool ? stored : stored == null` (F3).

**D1 dev panel** (source slice via `test/helpers/dart_source_slice.dart`, as `measurement_flag_off_identity_test.dart:425`):
- The toast and the status row read `KILLED` for a stored `false`.
- Mutation: `KILLED` -> `off`.
- Presence only (stated).

**S1 screen** (`test/features/train/log_exercise/log_exercise_screen_flip_test.dart`):
- **Setup:**
  - real `ActiveWorkoutScreen`;
  - `SeededNotifier` with a `WorkoutDayData` without warm-up/cool-down;
  - `lastPerformanceProvider` overridden;
  - Hive opened inside `runAsync`;
  - `renderFontsFirst` also renders `AppTypography.numeric` (Fraunces w700; without it `google_fonts` throws, R5A-06);
  - key absent.
- **Assertions:**
  - The LOG row is present and `interactiveCheckTiles` is absent.
  - Then `tester.runAsync(() => configBox.put(key, false))`, then `notifier.setElapsedSeconds(1)` to force a rebuild, then pump: the reverse.
  - With the key absent again, one exercise logged and one not, `scrollUntilVisible` FINISH, tap: `Nothing to save for: <name>`.
  - The header reads working counts, and with every set flagged warm-up the percentage reads `0%` (no throw).
    - Mutation: the screen computes `saved / total` inline instead of `workingProgress`.
- **Teardown:** unmount via `tester.runAsync(() => tester.pumpWidget(const SizedBox()))`.
- **Mutation:** `logMode = false` at `screen.dart:325`.

**Controller** (behavioural file, injected clock):

| Case | Expected | Mutation that reddens it |
|---|---|---|
| R1 | `reopen` at 1000 ms after an advancing LOG: ignored; at 1300 ms: reopened | window `kReopenGuard` -> `kRevealGuard` |
| R2 | LOG at 500 ms after a re-open: ignored | reopen stamps the `kLogInputGuard` window; no stamp on reopen |
| R3 | `reopen` on a not-done exercise with one checked set: noop, the set stays checked | drop the `isExerciseDone` check |
| R4 | after a LOG that revealed a partner, LOG at 550 ms: ignored; with no partner, LOG at 550 ms: allowed | `_lastAdvanceWindow` always `kLogInputGuard` |

**Notifier** (behavioural file):
- **`recordCardEdit`:**
  - values and marks land in one state change (a listener counts 1);
  - no write when nothing changes, or when `isSaved`.
  - Mutations: split into two `copyWith` writes (listener count 2); write without the no-change check; drop the `isSaved` guard.
- **`unlogSets(reopened: true)`:** adds the name; UNDO does not.
  - Mutation: always add.
- **`logSets` while `_completing`:** no change (un-awaited `completeWorkout` in fakeAsync, as test 11).
  - Mutation: drop the guard.
- **Cleanup:**
  - `swapExercise` drops the slot's keys;
  - `removeExercise` with three exercises, remove the middle: the keys of exercise 2 become `1-s-weight`/`1-s-duration`/`1-s-distance`;
  - `removeLastSet` drops all three field keys of the last set;
  - `copyWith` keeps both sets across `setElapsedSeconds`;
  - `startWorkout` clears.
  - Mutations, one each: no swap drop; a 2-part re-index; an exact-key `removeLastSet` removal; `copyWith` drops the field.
- **`wouldSaveSet` parity (U-D1):**
  - a fixture with a never-touched exercise, a re-opened one, an all-warm-up "done" one, and a `+`-after-LOG one (3 of 4);
  - assert `finishGuard` and `workingSetCounts`;
  - Mutation: drop the warm-up clause in `wouldSaveSet` (U-D1 reddens).
- **U-D1b parity (behavioural):** the same fixture through the real, awaited `completeWorkout` (`setUpHiveForTests`), reading the `exlog_*` rows from `HiveService.instance.workoutBox`.
  - Absolute expectations (R5A-01): A has 3 sets; D has 3 (of 4); a fifth exercise E (`sets: '3'`) with an extra checked key `4-3` (made with the unbounded `toggleSet`, `train_provider.dart:1508-1517`, plus `recordSetValues`) has exactly 4; B (untouched) and C (all warm-up) are absent.
  - It also asserts they equal `finishGuard`'s non-skipped names and the `saveableSetIndexes` lengths.
  - Mutations: `completeWorkout` re-inlined without the warm-up `continue`; `saveableSetIndexes` without the `maxSetLog` extension (fixture: a checked key beyond `e.sets`).

**Pure:**
- `isFaded` truth table (logMode, saved, checked, key).
- `prefilledSubline`/`liftedSubline`.
- `capNames` (0, 1, 5, 7 names).
  - Mutation: cap at 7 (the 7-name case reddens).
- `workingProgress` with total 0 (all warm-up): 0.0.
  - Mutation: drop the zero guard.
- `finishGuard` (partial, skipped, reopened, typed, nothing saved).
- Mutations: `typedUnsaved` ignores the suggested key (the returning-user untouched case reddens); `typedUnsaved` scans reps too (every untouched fixture exercise carries captured reps); `typedUnsaved` ignores the unchecked-set rule (the logged all-warm-up case reddens).
- Mutation: `finishGuard` treats any unchecked set as skipped (U-D1 `+`-after-LOG reddens).

**Card** (`log_exercise_card_test.dart`; the harness gains `onReopenExercise`, a `logMode` read of the container, and a `weight` parameter on `exercise()` (today hard-coded `'0kg'`)):

*RE-OPEN:*
- **A1** Tap LOGGED: re-opened (unchecked, values kept, `LOG 3 SETS ✓`, SWAP back).
  - Mutation: restore `&& !logged`.
- The existing review-mode test (`log_exercise_card_test.dart:139-146`) seeds `setInputValues`, so it does not pass as `null == null` once `recordCardEdit` skips on `isSaved` (R4A-10).
- **A3** Review mode: no `TAP TO RE-OPEN` text, the semantics node is not a button, and the hint is absent.
  - Mutation: show the subline unconditionally.
- **A4** Re-open + LOG = one LOG (the sets are checked again and `logSets` ran once).
  - Mutation: the card's re-open callback also calls `onLogExercise`.

*Fade:*
- **P1** New user: blanks are not faded. Type set 1: sets 2-3 mirror faded and set 1 is normal, in the same frame. Clear set 1: followers are blank and NOT marked.
  - Mutation: mark empty targets.
- **P2** Returning user: weights faded, reps not. Typing in one field clears only that field.
  - Mutations: the fade is never cleared; reps are marked.
- **P3** A real `tester.tap` on a faded field selects all. After `pump(600 ms)`, a second tap before typing re-selects (consecutive taps do not call `onTap`, R4A-05).
  - Mutation: drop `onTap` (the first-tap assertion reddens).
- **P4** Returning user: the subline reads `· PREFILLED`. Type set 1: `KG LIFTED`, while the followers stay faded.
  - Mutations: the subline ignores marks; the subline reads any working mark instead of the source's.
- **P5** Re-entry: type 62.5 into a prefilled 60, then dispose and re-pump with the same container. The text is 62.5 and normal; the untouched sets stay faded.
  - Mutation: restore the checked-only capture.
- **P5b** Clear a prefilled weight to blank, then dispose and re-pump: the field is blank (blocked `Add weight`), not the prefill.
  - Mutation: revert the LOG-mode null restore.
- **P6** Flag OFF: no fade, colours unchanged, no capture on keystroke.
  - Mutation: drop the `!_logMode` return in `_onFieldChanged`.
- **P7** The fade holds across a 1 s pump with a changed `data`, `−` then `+`, a warm-up toggle, swap, UNDO and RE-OPEN.
  - Mutation: the render ignores `isChecked`.
- **P8** Tap a faded field, `testTextInput.enterText('5')` then `('55')`: the same `EditableTextState` (`same(...)`) and `hasFocus` throughout.
  - Mutation: make the Semantics wrapper conditional.
- **P9** New user types 60 in set 1 (sets 2-3 mirror), then dispose and re-pump, then edit set 1 to 65: sets 2-3 read 65 and stay faded. Returning user (source suggested): the same re-pump, then edit set 1: followers keep the history value.
  - Mutation: drop the re-seed.
- **P9c** Returning user types 62.5 in set 1 (the source key clears; sets 2-3 keep the suggested 60), then re-pump and edit set 1 to 65: sets 2-3 stay 60 (R6-02).
  - Mutations: drop the text-equality clause; drop the source-not-suggested gate.

*Header hint, semantics, layout:*
- **H1** In LOG mode, `Tap to edit values` is absent; OFF shows it.
  - Mutation: drop the LOG-mode hide.
- **SM1** Semantics (`tester.getSemantics(...).getSemanticsData()`):
  - LOG, LOGGED, blocked and UNDO nodes each have `hasAction(SemanticsAction.tap)`.
  - The LOG node label includes the subline; the LOGGED label is `Logged`, and the node carries a custom action whose hint is `Re-open` (`customSemanticsActionIds`).
  - Runs under `tester.ensureSemantics()`.
  - A non-empty faded field has hint `Prefilled value` and its unit label; a normal field has no hint; a timed card's duration field says `SEC`; a blank field has no extra label.
  - The UNDO toast text node is a live region.
  - Mutations: drop `onTap:` from the button Semantics; drop it from the UNDO Semantics; drop the subline from the label; drop `liveRegion`; drop the field `label:`; hard-code `'KG'` (the timed `SEC` case reddens); make the field `hint` unconditional.
- **SM2** RE-OPEN on a card in the screen harness: `tester.takeAnnouncements()` contains `<name> re-opened`.
  - Mutation: drop the announcement.
- **L1** 320 dp × textScale **2.0**, empty `lastPerformanceProvider` (prefill from `exercise.weight`): no overflow for LOG-with-`· PREFILLED` and LOGGED-with-re-open. Proves height behaviour, not pixel width (Ahem font).
  - Mutation: restore `height: 44`.
- **L2** The same at 320 dp × 1.5 with a history fixture (`lastWeight: 60`): no overflow.
  - Mutation: remove the `Flexible` on the LAST row.
- **S2** (source pins on `_onReopenExercise`): it clears the UNDO toast only under `record.exerciseIndex == exIdx`, and calls `_focusExercise(exIdx)`. Presence only (stated).

*Repoint:* `:47` changes `1440 KG LIFTED` -> `1440 KG · PREFILLED`.

**Dialog** (`log_exercise_finish_dialog_test.dart`; `_showFinishDialog` is a part-file function, so it is driven through S1's screen; the layout case uses the screen at 320 dp):
- **U-D2** The re-opened and typed lines are in `warn`, the skipped line in `textDim`.
  - Mutation: swap the colours.
- **U-D3** 12 long names, 320 dp, textScale 2.0, keyboard inset, empty `lastPerformanceProvider`: no overflow, the first name visible, `+7 more`.
  - Mutations: restore the duration `Row`; `scrollable: false`; restore `maxLines: 2` (the first name is cut).
- **U-D4** Nothing logged (LOG mode): `Nothing logged yet. Log at least one set to complete, or cancel the workout.`, no lists, COMPLETE disabled (tapping it does nothing; the dialog stays).
  - Mutations: show the lists when `saved == 0`; leave COMPLETE enabled.
- **U-E1 (behavioural, notifier):** with Hive set up (`setUpHiveForTests`), a session with zero saveable sets runs the real, awaited `completeWorkout`. Expected:
  - no `wlog_*` row and no `exlog_*` row;
  - the schedule day's status is unchanged, and `total_workouts_done` is unchanged;
  - `isComplete` is false, and the timer still runs: the real `startWorkout` is called inside `fakeAsync`, and `fa.periodicTimerCount` is 1 before and 1 after the guarded `completeWorkout` (R7-03; `elapsedSeconds` reads `DateTime.now()`, which fakeAsync does not fake).
  - Variants: only warm-up sets checked (zero); a checked set with no captured values (zero); one saveable set (completes, `total_workouts_done + 1`); review mode (`isSaved`) still marks `isComplete`.
  - Mutations (R7-03): remove the guard; move it below `_timer?.cancel()` (the timer count reddens); drop `!state.isSaved` (the review-mode variant reddens); `hasSaveableSet` constant false (the one-saveable variant reddens).
- **U-E2 (dialog, OFF mode):** zero checked sets: the block line shows and COMPLETE is disabled. One checked set with values: the old dialog, unchanged. At 320 dp × textScale 2.0 with a keyboard inset, the blocked OFF dialog lays out without overflow (R7-01).
  - Mutations: gate the block on `logMode`; `scrollable: logMode`.
- **U-E2b (dialog, live re-check, R7-05):** the dialog opens with one saveable set; the test then un-logs it through the notifier and taps COMPLETE: the dialog stays, `ActiveWorkoutPersistence` keeps its snapshot, `onComplete` is not called, and nothing completes.
  - Mutation: drop the closure re-check.
- **U-E2c (dialog, LOG mode, R7-04):** blocked with a re-opened exercise: the block line and the re-opened line both show; no skipped line.
  - Mutation: return right after the block line.
- **U-E3 (pure):** `hasSaveableSet` truth table: none, warm-up only, one saveable, a checked set without values, only the SECOND exercise saveable, a checked key beyond `e.sets` (R7-06).
  - Mutations: `hasSaveableSet` ignores warm-ups; checks only exercise 0; `saveableSetIndexes` without the `maxSetLog` extension.
- **U-E4 (pure, R7-02):** `draftHasLoggableSet`: no exercise with sets (false); one weight exercise with a set (true); a cardio exercise (true: the synthetic set).
  - Mutation: `draftHasLoggableSet` returns true.
- **U-E5 (behavioural, R7-02):** `submitWorkoutDraft` on a draft with no sets, with Hive set up and a real `WidgetRef`: no `wlog_*`, no `exlog_*`, the draft is kept. The card with that draft shows `coachDraftNoSets` and its CONFIRM does nothing.
  - Mutations: drop the guard in `submitWorkoutDraft` (the `wlog_*` check reddens); the card's `onTap` ignores `canLog`.
- **U-D5** OFF: the old count line, no guard lines, not scrollable; at 390 dp × 1.0 the `MIN : SEC` label's top equals the duration fields' top (R6-01: at 360 dp the old Row already overflows under the test font).
  - Mutations: `scrollable: true`; `spacing: 6` (the label wraps, so the check reddens).

**Existing pins to keep green:**
- `set_add_append_test.dart`;
- `readiness_checkin_behavioral_test.dart`;
- `rep_input_validation_test.dart`;
- `duration_controller_seeding_writer_to_reader_test.dart`;
- `exercise_plate_badge_sites_test.dart`;
- the screen slices at `active_workout_set_logging_behavioral_test.dart:420-540`.

**Full gate loop** before the diff review (4.12.8): `flutter analyze lib/`, `TZ=Asia/Kolkata flutter test`, `sh scripts/pre-commit.sh`.

## 7. Merge order, exposure, rollback, device check

**Merge order:** PR #134 first (main green), then this PR.

**Exposure:**
- This reaches every signed-in user of the next release build, and of the web app. `vercel.json` `ignoreCommand` builds only `main`, so the merge very likely auto-deploys the flip to app.icanbefitter.com BEFORE the device check (R4B-14). Web testers see it first.
- Pre-launch, these are testing accounts only (root CLAUDE.md §1).
- Before a wider audience (Play internal testing onward), a remote kill switch is a founder decision (ledger `EXPOSURE`).

**Kill switch and rollback:**
- The kill switch is the debug dev panel only. Release builds have no switch.
- Sign-out clears `configBox` (`user_repository.dart:1211`), which turns the flag ON again.
- Rollback: revert the getter line, then ship a new build (Android build + Play upload latency); on web the fast path is Vercel "promote previous deployment" (no code change), then the revert merge redeploys `main` (browser cache behaviour UNVERIFIED).
- Code shared by both paths: the `SetInputRow` signature and the always-present Semantics wrapper (now with a unit label), the `completeWorkout` helper extraction and its zero-set guard (U-E), the dialog's zero-set block (U-E), the `logSets` `_completing` guard, the duration `Wrap`, the dialog's `scrollable: logMode || blocked` and the COMPLETE live re-check, the LAST-row `Flexible`, the UNDO Semantics `onTap`, and the `_showFinishDialog`/`_buildHeader` parameters. P6, U-D5, U-D1b, L2 and the full suite cover the OFF behaviour.

**A12** (OI-348, replaces `open_issues.md:6148`), on the release build after merge:

*Accounts:*
- **New account:** blank blocks, set 1 mirrors faded, LOG, UNDO, `All exercises logged.`, gold FINISH, receipt.
- **Returning account:**
  - faded weights, normal reps, `· PREFILLED` (does it read as a total or a weight?);
  - tap selects all, on Gboard and on the Samsung keyboard;
  - no keyboard flicker on the first keystroke into a faded field;
  - type one field and it turns normal; then LOG;
  - a WELCOME BACK (detraining or readiness-eased) prefill is faded.

*RE-OPEN:*
- after > 5 s;
- double tap on LOGGED;
- on the last exercise;
- in a superset during the reveal scroll;
- while another exercise's UNDO toast shows;
- then `+`/`−`;
- then FINISH without re-LOG: the re-opened line names it; then COMPLETE and check the receipt;
- the "did it register?" bounce: tap LOG on the last exercise, then tap again at about 1 s and at about 2 s.

*FINISH and counts:*
- `+` after LOG, then FINISH: `Partly logged`.
- FINISH with one exercise skipped (calm line).
- FINISH with nothing logged: COMPLETE disabled, the block line readable at the largest font with the keyboard up (OFF and LOG); CONTINUE and Cancel work.
- Coach chat: a workout draft with no sets: CONFIRM disabled with the reason; DISCARD works.
- All sets flagged warm-up: the percentage reads 0%, no crash.
- A warm-up flagged: header, percentage and dialog all agree.

*Navigation:*
- Leave + RESUME: logged, typed-unlogged and fade all kept.
- Scroll far away and back with typed values, and with a faded value cleared to blank.
- Typing latency in a faded field on a low-end phone.
- Kill the app: the workout is gone (expected).
- Review mode: no re-open text.

*Exercise types and edits:*
- timed, cardio (decimal minutes), distance, bodyweight (LOG logs prefilled reps), weighted_bodyweight, custom;
- swap/add/remove, then LOG.

*Environment and accessibility:*
- a second account on the same device;
- coach mid-workout;
- TalkBack: double-tap activates LOG, LOGGED and UNDO; the LOG toast is read; RE-OPEN announces `<name> re-opened`; a field announces its unit (`SEC` on a timed card); a faded field announces `Prefilled value`;
- a LOG tap about 0.5 s after an accidental re-open (ignored, expected);
- re-open an exercise after scrolling it far away, amend set 1: sets 2-3 follow;
- FINISH with typed-but-unlogged values: the typed line names it;
- cardio decimal minutes typed, scroll away and back;
- web smoke on app.icanbefitter.com right after the deploy;
- the FINISH duration row on a 360 dp phone at 1.0 font (one line expected);
- TalkBack: editing a logged set within the 5 s toast re-announces the toast's KG total (expected, mildly noisy);
- largest font on a 320 dp phone (card and FINISH dialog; also 1.3x on 360 dp);
- bright-light legibility of faded vs normal;
- web at phone width.

## 8. Docs, board, ledger, obligations

**Code-adjacent docs:**
- the `log_exercise_flags.dart` comment;
- `lib/features/train/CLAUDE.md`, row `active_workout_set_logging`: LIVE default ON, RE-OPEN, `suggestedInputs`/`reopenedExercises`, full capture in LOG mode, the FINISH guard via `wouldSaveSet`, "faded = app-filled weight/duration/distance; reps always normal". Check the budget with `check_context_artifact_budget.dart`, and `--record` if intended;
- `docs/naming_conventions.md`: flag polarity; `RE-OPEN`/`reopen` (distinct from the existing review-mode `reopenWorkout()`, `train_provider.dart:1498`); `suggestedInputs`, `reopenedExercises`, `isFaded`, `kRevealGuard`, `kReopenGuard`, `recordCardEdit`, `wouldSaveSet`, `saveableSetIndexes`, `workingProgress`, `workingSetCounts`, `finishGuard`, `FinishGuard`, `typedUnsaved`, `reopenedUnsaved`, `capNames`;
- `docs/architecture/functionality-flow.md`: new `TRAIN-06a`;
- `WardroomCopy`: new constants, and the `activeLoggedLabel` comment.
- `lib/features/ai_coach/CLAUDE.md`, row `coach_derived_completion` or the pieces list: `submitWorkoutDraft` and the confirm card share `draftHasLoggableSet` (R7-02).

**SoT registry** (`docs/sot_registry.yaml`), entry `active_workout_set_logging`:
- new writers: the `reopen` path, `recordCardEdit`, `unlogSets(reopened)`;
- new readers: `isFaded`, `prefilledSubline`, `finishGuard`, `workingSetCounts`, `wouldSaveSet` (including `completeWorkout`);
- the flag comment at :12711-12712;
- the sentence saying `logSets` is "deliberately NOT guarded by `_completing`" (~:12725) is rewritten (R5A-08).
- The ranges of EVERY concept citing `train_provider.dart`, `exercise_card.dart`, `screen.dart`, `set_input_row.dart`, `finish_dialog.dart` or `header.dart` are re-baselined (for example `workout_templates`, `weekly_streak_counter`). Run `check_sot_registry_parity.dart` until clean.

**Ship-dark ledger** (`docs/ship_dark_pending_review.yaml`):
- `flip_reviewed: true` (full x2 converged, plus a B-pass with no open P0/P1);
- `flip_commit` stamped after landing;
- precondition 3 amended (founder 2026-10-20);
- the entry stays until the OFF-path OI closes.

**Board:**
- Mint the OFF-path removal OI with `MINT_OI_TRANSPORT=git sh scripts/mint_oi.sh` (Blocked on: A12).
- **OI-361** (minted 2026-10-20) is built here as U-E and CLOSED in this batch: moved to `closed_issues.md` with the commit. Diagnose doc (full template; a pre-existing correctness bug on both paths) with `closes-diagnose:`, and `closes-oi: OI-361`.
- Trim OI-357 (faded prefill moved here).
- Rewrite OI-348 A12.

**Closure ledger** `docs/audit/log-exercise-flip.closure.yaml` (Gate 40):
- `REOPEN`, `REVEAL-GUARD`, `FADE`, `FULL-CAPTURE`, `RESTORE-BLANK`, `SUBLINE`, `LAYOUT`, `LAST-ROW-OVERFLOW`, `SEMANTICS`, `UNDO-SEMANTICS`, `FINISH-GUARD`, `SAVE-PREDICATE`, `HEADER-COUNTS`, `LOG-COMPLETING-GUARD`, `DIALOG-DURATION-WRAP`, `FLIP-CODE`, `DEV-PANEL`, `SCREEN-TEST`, `TESTS`, `MUTATION`, `DOCS`, `REVIEWS`, `PRECONDITION-3-AMENDED`, `EXPOSURE`;
- `REPS-BODYWEIGHT-SIGNAL` (`verified_clean`, evidence: accepted founder decision 2026-10-18, stated in §5 and the train CLAUDE.md row);
- `TALKBACK-FEEDBACK`, `MIRROR-RESEED`, `TYPED-UNSAVED-LINE`;
- `ZERO-SET-COMPLETION` (`closed_in_commit`: U-E, OI-361);
- `CHAT-DRAFT-ZERO-SET` (`closed_in_commit`: R7-02, the `submitWorkoutDraft` guard and the confirm card);
- `FLIPPED-BUILD-CHECK` (`blocked_on_user`);
- `OFF-PATH-REMOVAL` (`blocked_on_user`).

**Reviews and retrospective:**
- The plan-review record `docs/plan-reviews/log-exercise-flip.md`, covering all rounds.
- The B-pass review file plus a same-dated `tuning-history.md` entry (5.1).
- The `project_log_exercise_flip` retrospective.
- Update the memory note that says "default OFF".
- Skill self-evolution check: the R3A-01 lesson, "`selectAllOnFocus` does not fire on tap; spike Flutter focus behaviour before planning on it", goes to the debugging bug-classes or the common pitfalls.

## 9. Out of scope

- per-set last values, once-only hints, auto-scroll (OI-357 remainder);
- deleting a set or exercise from a SAVED workout;
- OI-358, OI-352, OI-353;
- removing the OFF path (minted OI);
- a remote kill switch.
