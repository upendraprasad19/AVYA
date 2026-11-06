# OI-358: one exercise name per workout day

Branch `oi358-unique-exercise-names`, based on `main` @ `d27bf032`. Fix tier **M** (touches
`lib/core/services` and `lib/features/ai_coach`). Blast radius **account**
(`blast_radius_from_diff.dart` over the touched files; re-run once the new helper exists).
Execution mode: **inline**, decided at batch start (§4.12.7). Client only: no Edge Function
change, no deploy, no migration. Founder decisions (2026-11-06): fix every door in one branch;
a name already in the workout is shown greyed out, not hidden.

## 1. The defect

The Active Workout screen keys each card by exercise name: `_exerciseKeys.putIfAbsent(exercise.name,
...)` (`lib/features/train/screens/active_workout/screen.dart:622`), used at `:665`. The comment at
`:75-77` says this is deliberate, so the key follows an exercise across a reorder. Two cards with one
name share a GlobalKey.

**Reproduced 2026-11-06** with a scratch test over `pumpScreen` (real screen, test build):

| Case | Result |
|---|---|
| A: `addExercise` with a name already in the session | `Multiple widgets used the same GlobalKey` |
| B: `swapExercise` into a name in another slot | same |
| C: session started from a day holding the name twice | same |
| D: control, two different names | no exception |

Release-build behaviour is **not measured**. Asserts do not run there, so the outcome is unknown,
not "no crash".

A second reason, independent of the key: `WorkoutWriteService.exlogKey`
(`lib/core/services/workout_write_service.dart:1695`) hashes `exerciseName.toLowerCase().trim()`, so
two same-name cards would save to one log row.

Other code already assumes unique names: `reopenedExercises` (a set of names) and the UNDO toast's
name check (OI-358 entry; diagnose `c7d2a9` line 73).

Bug history (§4.1.5), searched on the built index plus the raw docs for token, concept and failure
shape. No prior diagnose has this crash: `Multiple widgets used the same GlobalKey` and `_exerciseKeys`
appear in no diagnose-doc, in `common-pitfalls.md` or in the debugging skill. `a1d7c3` is about two chat
cards; `c7d2a9` only cites OI-358.

**Related, not a recurrence:** `b3c8d2` (2026-05-12), templates showing 14-15 rows with 4-5 distinct
names on a real account. Different root cause (cloud `template_exercises` tail rows after a shrink),
fixed by the tail vacuum that is still live (`sync_workout.dart:1954`). It matters here as evidence:
duplicate names in a template have reached a real account through RESTORE, a path no picker controls.
That is why U3 exists. The diagnose-doc cites it in `related_bugs:`.

## 2. The rule this batch makes true

> Within one workout day, in the session and in a stored row, no two entries share
> `exerciseNameKey(name)`, where `exerciseNameKey` is `name.toLowerCase().trim()`, the same
> normalisation `exlogKey` uses.

Deliberately wider than the GlobalKey's exact match: `"bench press"` and `"Bench Press "` do not
collide on the key but do collide on the log row.

One declared exception: a row with no name is not an exercise identity, so nameless rows are never
dropped from a stored row. `_normalizeExercises` writes such rows as `'Unknown'`, and
`_parseExerciseMaps` reads them as `'Unknown'`, so U3 still collapses them at start. The screen is safe
either way.

Keying cards by position is rejected: it breaks the reorder behaviour at `screen.dart:75-77`, and two
same-name cards would still write one log row.

## 3. Doors (writer census)

Session list writers in `train_provider.dart`: `startWorkout` (:1501), `swapExercise` (:1732),
`addExercise` (:1749). The rest (:1805 remove, :1828 move, :1846 and :1874 set counts, :1943 superset)
cannot add a name. `active_workout_persistence.dart` does not store exercises.

Stored-day writers that can add a name: `SwapService.swapExerciseInDay`
(`lib/core/services/swap_service.dart:413`), `TemplateService.assignTemplateToDate`
(`lib/core/services/template_service.dart:82`). Others only remove or rewrite (`shortenDay`,
`auto_appended_custom`, `deload_evaluator`, superset persist).

| # | Door | Writer | Today |
|---|---|---|---|
| 1 | Train: Add exercise, incl. its create-custom | `addExercise` | no check |
| 2 | Train: Swap sheet, incl. create-and-auto-swap and its UNDO | `swapExercise` | hides only the outgoing name |
| 3 | Train: template builder | `_exercises.add` (`template_builder_screen.dart:330`) | no check |
| 4 | Coach: `swapExercise` tool | `swapExerciseInDay` | no check |
| 5 | Coach: Swap quick action | `showCoachSwapSheet` -> same tool | hides only the outgoing name (`swap_exercise_coach_sheet.dart:124-152`) |
| 6 | Coach: injury swap | `InjurySwapPlanner` -> `swapExerciseInDay` | `_findSubstitute` returns the first match and never sees the day |
| 7 | Coach: `createCustomTemplate` | `WorkoutRepository.createTemplate` (:1726) | checks the template NAME only (:1760-1775) |

Carriers, not doors. They pass on a duplicate a template already holds:

- `assignTemplateToDate`. All three routes reach it: `tool_dispatcher.dart:1537`,
  `schedule_template.dart:176`, `template_builder_screen.dart:413`. `_normalizeExercises` (:318) maps one
  row to one row. Guarded by U7.
- Cloud restore hydration: `sync_workout.dart:2720-2735` builds `hydratedExercises` from
  `template_exercises`, written at `:2849`. This never calls `assignTemplateToDate`. It is deliberately
  NOT edited: U3 covers it, and changing sync would move the batch to tier L and pull in §4.6 for a
  path that can only display a duplicate.

A template cannot be started directly. Its card offers EDIT, SCHEDULE and delete only.

**No door, checked:** coach `logSet` and the workout log card merge on `exlogKey` (`logExercise`,
:181) and never touch the plan list. `shortenWorkout`, `rescheduleWeek`, `swapWorkoutDays`,
`pausePlan` do not add a name. `createCustomExercise` writes the library only. There is no add-exercise
tool (registry names read 2026-11-06).

**Plan generator, measured:** `generateV4` over a shuffled sample of 580 of the 12,960 combinations of
goal x tier x days x level x minutes x phase x injury (9,892 workout days): **0** within-day
duplicates, 0 generation failures. `hotel_workout_planner.dart` calls the same generator. This is a
sample, not proof, which is one reason for U3. The repeat-phase pin path (`buildPinnedDays`,
`exercise_selector.dart:1006`) was READ, not measured: it dedupes per variant.

## 4. Units

### U1. The shared rule (`lib/core/utils/exercise_name_identity.dart`, new)

Pure, no Hive:

- `String exerciseNameKey(String name)`
- `String? exerciseRowName(Map row)`: a non-empty `exercise_name`, else a non-empty `name`, else null
  (an empty `{}` slot reads null). Both shapes exist: `_normalizeExercises` and `createTemplate` write
  `exercise_name`, library rows and the builder use `name`, restored templates carry both
  (`sync_workout.dart`).
- `Set<String> exerciseNameKeysOf(Iterable<String?> names)`
- `List<T> firstPerExerciseName<T>(Iterable<T> rows, String? Function(T) nameOf)`: keeps the first of
  each name, keeps order, keeps rows whose name is null or empty.

`exlogKey` is NOT changed (Gate 17 pins its formula). A parity test pins that two names share an
`exerciseNameKey` exactly when they share an `exlogKey` on one date.

### U2. Session writers (`train_provider.dart`)

A plain `bool` cannot work: `swapExercise` already returns early on a bad index (:1682), and that must
not read as "already in this workout". Both return `enum SessionExerciseChange { applied, nameTaken,
invalidSlot }`, and only `nameTaken` shows a message.

- `addExercise`: `nameTaken` and no state change when the name is in the session.
- `swapExercise`: `nameTaken` and no state change when the name is in a slot OTHER than
  `exerciseIndex`. The same slot stays allowed (UNDO, a re-pick). `invalidSlot` for the existing guard.

### U3. Last line at start (`startWorkout`, `train_provider.dart:1494`)

`firstPerExerciseName(day.exercises, (e) => e.name)` before the readiness drop, so a day that already
holds a duplicate (restore, another device, an older build) opens instead of failing. Logs one
`active_workout_duplicate_name_dropped` event when it drops anything, through
`unawaited(ErrorTelemetry.logEvent(...))` (`train_provider.dart` needs the import); the message is the
COUNT only, never an exercise name. The stored row is not rewritten. A Train day card may still list the stored
duplicate: display only.

`startWorkout` is the only place a stored day becomes `ActiveWorkoutData.exercises`. If a dropped row
held a `superset_group`, its partner is left alone in the group. That is the same state
`removeExercise` already leaves today (it does not touch the partner), so U3 adds no new state.

### U4. Train pickers

All three show a taken row greyed out with the tag `ALREADY IN WORKOUT` (builder: `ALREADY IN
TEMPLATE`). It stays findable by search and cannot be tapped. Names are captured when the sheet opens;
the writers stay the real guard.

- `_ExercisePickerSheet` gets `takenNames`; row `onTap: null` (`exercise_picker_sheet.dart:265`).
- `ExerciseSwapSheet` gets `takenNames`; `_SwapItem` gets a taken state in which BOTH tap targets are
  dead: the row's `InkWell` (:412) and the `SELECT` button (:489), which the label replaces. Passing EVERY session name also covers the outgoing
  exercise when it is a custom row, which `_loadExercises` leaves in the custom list today.
- `_ExerciseSearchSheet` in the builder gets `takenNames` from `_exercises` via `exerciseRowName`; row
  `onTap: null` (:713).

Copy lives in `lib/core/copy/wardroom_copy.dart`, the same home as `activeMovedTemplate`, never inline.
No new `.getAll()` or `getCustomExercises(` line in any picker file (`check_exercise_seams.dart` counts
them). `template_builder_screen.dart` is 725 lines against the 800 ceiling of
`check_god_screen_max_lines.dart`; its changes must fit under that.

**Every call site branches on the result.** Today all four assume success and run invalidates, pops
and the UNDO snackbar unconditionally (`swap_sheets.dart:12-35`, `:58-91`, `:189-218`, `:220`).

A refusal can still reach the user through a path no row controls: create-custom with a name equal to
a session name (the custom guard at `workout_repository.dart:1619-1628` compares ids within customBox,
so a custom can share a library name), and the swap UNDO after the outgoing name was re-added.

| Site | On refusal |
|---|---|
| `_showExercisePickerSheet` onSelect | Pop the picker, then show the message. Capture `ScaffoldMessenger.of(context)` from the SCREEN `context` at the top of the function, before `showModalBottomSheet`. The create sheet has already popped itself (`create_custom_exercise_sheet.dart:340-342`) and the picker's `ctx` is still mounted, so the existing pop is correct. |
| `_showSwapSheet` onSelect | No invalidates. Pop, then the message, same capture. |
| `_openCreateAndAutoSwap` | No invalidates and no UNDO snackbar. The message goes on the same messenger the UNDO snackbar uses. |
| UNDO closure | See below. |
| builder `_showExerciseSearch` onSelect (:330) | No `add`. `ScaffoldMessenger.of(context)` from `State.context`, then the existing pop. |

The message is `"<name>" is already in this workout.` (builder: `... in this template.`). Bugs
`s1n4c0` and `6c2f91` live on these paths, so no site adds or removes a pop.

**A refused create-custom keeps the custom row.** It is a library item the user asked to create, it is
useful later, and pre-checking inside the shared sheet would add a path for a rare case. Accepted.

**UNDO resolves its slot at tap time.** The closure captures `exerciseIndex`. A reorder cannot stale it,
because a move hides this snackbar (`screen.dart:146-149`). A REMOVAL can: another card's swap sheet can
call `removeExercise` during the 5 s window, which shifts later indexes and does not hide the snackbar,
so UNDO overwrites a neighbour and wipes its checked sets (existing defect, same closure this batch
edits). It looks up the slot holding `newName` in current state. No such slot: nothing happens.
`nameTaken`: the message.

**The builder reads both row shapes (same widget, same batch).** `ExerciseCard` at :287 reads only
`name`, and :291-296 read only `prescribed_*` and `default_*`. Rows from `createTemplate` carry
`exercise_name`, `sets`, `reps`; restored rows carry `sets`, `reps`. So a coach-made template should
open in EDIT as `Unknown` with 3 x 10 shown whatever was saved. Display only, code read. The card uses
`exerciseRowName`, and `sets` / `reps` join the fallbacks, parsed tolerantly (`int.tryParse('${...}')`,
`reps` through `'$v'`), never `as int?`: `_normalizeExercises` still handles a String `sets`, and
diagnose `a2f9e1` records that shape reaching Hive. This is a separate defect and gets its own lines in
the diagnose-doc (rule 22).

### U5. Coach swap (`swap_service.dart`, `tool_dispatcher.dart`, `swap_exercise_coach_sheet.dart`)

- `swapExerciseInDay`: once the target is resolved, compare the name that would actually be written,
  `(newLib['name'] as String?) ?? toExerciseId` (:552), against every slot but `matchIndex`, via
  `exerciseRowName` (slots can be `{}`). Throw
  `SwapExerciseException('exercise_already_in_workout', ...)`. Nothing is written.
- `_swapExerciseErrorMessage` (:1883) gets the case. The `default` branch would also show `e.message`;
  the case gives the coach today's wording.
- `_substitutesFor` marks taken options; `_tile` takes a nullable `onTap` and a label. Today's names
  come from the sheet's `_today`.

### U6. Injury planner (`injury_swap_planner.dart`)

`_findSubstitute` takes `takenNames`. `plan()` starts each date with that day's names and adds every
substitute chosen for that date, at both call sites (:84, :103). Both are per date: one substitute may
repeat across dates. A swapped-out name stays taken for that date (conservative, and simple). With
nothing left, `sub == null`, which is today's behaviour: the exercise stays and no swap is shown.

Execution stays consistent with the preview: `_executeModifyWorkoutForInjury` runs the cached swaps in
plan order, and every substitute is distinct from the day and from each other, so the U5 guard can only
fire if the day was edited between preview and confirm. The dispatcher already collects that into
`partial_errors`.

OI-403 (the planner ignores `injury_contraindications`) is a different defect in the same function.
This edit must leave its fix a one-line addition, and it stays open.

### U7. Templates (`workout_repository.dart`, `template_service.dart`)

- `createTemplate`: a pre-pass over every day BEFORE the first `box.put` (:1856) throws
  `CreateTemplateException('duplicate_exercise', ...)`, naming the exercise and the day. A check inside
  the loop would leave a partial multi-day template. The pre-pass applies the loop's own skip rule
  (:1800-1805): a row with an empty `exerciseId` or `exerciseName` is ignored, so it cannot refuse a row
  the loop would have dropped. The same name on two different days stays allowed. The dispatcher already
  shows `e.message` (:1465-1469).
- `assignTemplateToDate`: `firstPerExerciseName` over the RAW `tmplMap['exercises']` via
  `exerciseRowName`, BEFORE `_normalizeExercises`. On its result two nameless rows would both read
  `'Unknown'` and one would be dropped. Keep-first, not refuse: refusing would leave a saved template
  impossible to schedule, on three routes. `exercise_count` is on the template, not the scheduled row,
  so it is unaffected. `_normalizeExercises` drops `exercise_id`, so this compares by name.

## 5. Not changing

- No server-side check, so no EF deploy. The tools' zod schemas stay as they are; the client refusal
  is the guard and the coach shows its message.
- `plan_generator.dart` (rule 14).
- `sync_workout.dart`: the restore carrier in section 3.
- Stored rows and saved templates are not healed in bulk. U3 and U7 make them safe to read. Every account
  is a testing account (CLAUDE.md §1). Added by the B-pass: the builder keeps the first per name on load,
  so a Save from EDIT cannot write a restored duplicate back.
- Warm-up and cool-down lists: rendered separately, not name-keyed by `_exerciseKeys`.

**§4.6 does not apply.** That protocol covers payment, sync, auth, AI prompt and plan generator. This
batch edits none of them: no prompt or tool description changes, `sync_workout.dart` is untouched,
`plan_generator.dart` is untouched, and `injury_swap_planner.dart` is a coach-side planner outside
`plan_engine`. Each change only refuses or drops a duplicate name, which on `main` raises an exception
on the Active Workout screen, so there is no working old path to preserve behind a flag.

## 6. Tests

Rule 21: each guard mutated once, each mutation confirmed applied, the diagnose-doc states what was
mutated and how many tests went red. A compile error is not a kill.

Amended at build time, two things are stated as NOT pinned: `_showSwapSheet`'s `nameTaken` message is
unreachable through the UI (a taken row cannot be tapped), and "no provider invalidation on a refusal"
is not asserted (an extra invalidate only re-reads).

`test/contracts/exercise_name_unique_in_day_behavioral_test.dart`:

1. `addExercise`: refuses same name, other case, trailing space; state unchanged; distinct name true.
2. `swapExercise`: refuses another slot's name with `checkedSets`, `setInputValues`, `suggestedInputs`
   unchanged; same slot allowed.
3. `startWorkout`: keeps the first, keeps order, logs once with a count and no name; no event for a
   clean day.
4. `swapExerciseInDay`: throws the code; stored row byte-identical; same slot allowed; a target given
   by id whose NAME is already in the day is caught.
5. Injury planner: two affected exercises of one category get DIFFERENT substitutes; none is in the
   day; the same substitute on two dates is allowed; nothing left gives no swap.
6. `createTemplate`: a duplicate on day 2 of 2 writes ZERO rows; one name across two days is accepted;
   a duplicate name on a row the loop skips (empty id) does not refuse.
7. `assignTemplateToDate`: a duplicate template lands with one row, order kept; two nameless rows both
   survive.
8. Parity: `exerciseNameKey` vs `exlogKey` grouping.
9. `exerciseRowName`: `exercise_name` wins, `name` is the fallback, empty reads as null.

Widget tests under `test/features/train/`, plus `test/ai_coach/` for the coach sheet: greyed row
present and findable by search, tap does not call `onSelect`, an untaken row still works, for all
four pickers, tapping the row body as well as any button. Refusal paths: create-custom collision on add
and on auto-swap (message shown, no UNDO snackbar), UNDO after re-add, UNDO
after `removeExercise` on an earlier slot hits the right slot, builder refusal. `invalidSlot` shows no
message. Builder display: an `exercise_name` / `sets` / `reps` row shows its real name and numbers,
including a String `sets`. `TemplateBuilderScreen` has no test harness yet, so this adds one
(`ProviderScope`, `MaterialApp`, `seedLibrary`). `ExerciseSwapSheet` and `CoachSwapSheet` are public; the
Active Workout picker is reached through `pumpScreen`.

Screen regression via `pumpScreen`: cases A and B from section 1 raise no exception and render one card
per name. Case C calls the real `startWorkout` with a day holding the name twice, then pumps. These are
the tests that go red on `main`.

Mutants beyond deleting a guard: the other-slot exclusion in both swap writers; `toLowerCase` and `trim`
separately; per-date reset of `takenNames`; moving the `createTemplate` check into the write loop;
dropping the skip rule from the pre-pass; dedupe after `_normalizeExercises`; keep-first vs keep-last;
`exercise_name` vs `name` order in `exerciseRowName`; each call site's branch on the result;
`invalidSlot` read as `nameTaken`; UNDO by captured index.

## 7. Docs and board

- SoT registry concept `exercise_name_unique_in_day` with a `behavioral_test_path`.
- `lib/features/train/CLAUDE.md` and `lib/features/ai_coach/CLAUDE.md` rows.
- Diagnose-doc `docs/diagnoses/2026-11-06-exercise-name-unique-in-day-<id>.md` with
  `touched_layers_checked`.
- OI-358 retitled to cover every door and appended to `closed_issues.md` (append, never rewrite; check
  diff-stat deletions).
- `docs/audit/oi358-unique-exercise-names.closure.yaml` (§4.2: 7 units), every entry terminal.
- `docs/plan-reviews/oi358-unique-exercise-names.md`, and a self-initiated `/code-review` before the
  merge (account tier).
- `docs/naming_conventions.md`: the new terms (§4.7).
- SoT `line_range`s: this batch shifts lines in files the registry cites. After the LAST edit, run the
  registry parity check and recompute from anchors, never by hand.
- Re-baseline `check_context_artifact_budget.dart` for the nested CLAUDE.md rows (§5).
- `common-pitfalls.md` row and a debugging-skill entry only if the batch surfaces a new class (§5.1).

**Before any edit:** grep `test/` for the literals being touched. These read the edited files as text:
`swap_undo_snackbar_dismisses_test.dart` (non-greedy regexes over `_showSwapSheet` and
`_openCreateAndAutoSwap`, so no `}` at column 0 inside them), `swap_exercise_logging_type_behavioral_test.dart`,
`exlog_exercise_id_swap_threading_test.dart`, `test/safety/null_guard_test.dart`,
`swap_undo_snackbar_modal_pop_test.dart`, `swap_add_exercise_double_pop_behavioral_test.dart`,
`active_workout_superset_persist_behavioral_test.dart`, and `test/train/swap_logging_type_test.dart` (added
at build time; the full suite caught it). Repoint, never loosen.

## 8. Review log

Round 1 (context-blind, code only): verdict `needs_changes`. Accepted after checking each against the
code: every call site assumes success, with no messenger on the add path (P1, U4 table); restore
hydration is a carrier the census missed (P1, section 3); dedupe after `_normalizeExercises` eats nameless
rows (P2, U7); the pre-pass must copy the loop's skip rule (P2, U7); a `name`-only stored row is not a
real shape (P2, test 4); no exercise name in the event (P3, U3); §4.6 must be addressed (section 5);
UNDO's captured index (P3, fixed in U4 because the same closure is edited). Author's own correction in
the same round: the first bug-history search ran against an index that did not exist in this worktree,
and `b3c8d2` was missed.

Round 2 (fresh context-blind reviewer, on the plan above): no P0, no P1, verdict `needs_changes` on P2
and P3 items, all checked against the code and applied. The UNDO rationale was wrong (a move hides that
snackbar; a removal is what stales the index). A `bool` would have shown a false "already in this
workout" on a bad index, hence the enum. `sets` must parse tolerantly. Both tap targets of `_SwapItem`
must die. Section 7 gained the closure ledger, record, glossary, SoT range and source-pin steps. Section
2 declares the nameless-row exception. Rounds 1 and 2 surfaced no shared root issue and the second
found nothing material, so the plan is converged for §4.12.1.
