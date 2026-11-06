# Active workout: ⇄ swap + ⇅ move — Implementation Plan (Unit 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended here, see "Execution mode") or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** In the active workout, replace the `⇄ SWAP` text chip with two icon controls (`⇄` swap, `⇅` move), add a tap-to-place move mode that slides one exercise to another slot (session-only), make a swap keep the slot's superset group, persist superset groups by exercise identity, and show a once-per-account first-use hint.

**Architecture:** Pure functions and one plain-Dart controller (`MoveModeController`, same extraction idea as `LogExerciseController`) hold every decision; the notifier gains one apply method; the card and screen are thin shells over them. One boolean flag lives in the account's `userBox` through `MigratedKey`. No import cycle: new files under `lib/features/train/services/` import `train_provider.dart`, never the reverse.

**Tech Stack:** Flutter, Riverpod (hand-written providers), Hive via `MigratedKey`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-21-active-workout-swap-move-design.md` (read it first; this plan only records what it leaves to the builder, and the "Spec amendments" below win where they differ). Mockup: `docs/mockups/2026-10-21-exercise-swap-and-move-icons-v4.html` (local, gitignored).

## Execution mode (decided at batch start, §4.12.7)

**Inline (superpowers:executing-plans), one worktree (`swap-move-design`), one writer.** Tasks 4-6 all edit `exercise_card.dart` / `screen.dart` and depend on each other's names; parallel worktrees would conflict. Not switched mid-batch.

## Spec amendments (apply to the spec file in Task 7; each came from plan review)

1. **Animation:** the list reorders instantly (it is a plain `ListView` of GlobalKey'd columns; a 220 ms slide would need a different list widget). The moved card gets a gold highlight that fades in over 400 ms, is held until the screen clears the flag at 1000 ms, and fades out over 400 ms (≈1.4 s); targets pulse (1.7 s); no new collapse animation (cards use their existing expand/collapse). Reduce-motion ⇒ pulse and ring are static, and the highlight is the same 1000 ms hold with `Duration.zero` transitions (a plain border). The founder's decision "slide" is about *where things end up*, which is unchanged.
2. **Hint placement:** the callout is its own `ListView` child above the first card (never inside a card's keyed `Column`, which would recreate card State and drop typed input when it disappears). It shows only while no set is checked, so the ringed first not-done card is index 0.
3. **Move-mode taps and icons, per role:** source card = ⇄ + filled ⇅ + "MOVING" pill (⇄ cancels move mode, then opens the swap sheet; ⇅ or a header tap cancels); target card = "MOVE HERE" pill only, no icons, whole header (plate, name, chevron) places; done card = its `✓ DONE` chip, dimmed, every tap target inert (chip, plate). Header long-press (superset pairing) is disabled in move mode (card-side only). ⇅ is hidden while superset-grouping mode is on and in review mode (`isSaved`).
4. **Decision 8 wording:** persisted superset groups are identical to today's whenever the order is unchanged and no swap/add/remove happened; after those, the new write is *more* correct than today's index write.
5. **Header back arrow** (`context.pop()`, bypasses `PopScope`) leaves the screen and ends move mode silently; only system back cancels move mode.
6. **Same account, sign-out/in:** `clearAllData()` clears `userBox`, so the hint shows again after re-login or reinstall. Accepted.
7. **Swap carries the group in `swapExercise` only** (spec L66 says "one field in `swap_sheets.dart` + `swapExercise`"): `swap_sheets.dart` is not edited; the notifier is the single writer.
8. **A move clears the LOG undo record** with `_clearLogUndo()` (spec L63 says not to remap it and accepts the toast disappearing): the record is index-keyed and a move shifts indices, so clearing is the safe form of "toast disappears".
9. **Hint is persisted only after it was actually shown** (or an icon was tapped): a first workout where the hint was never visible (e.g. one exercise) does not burn the flag.

Spec lines to edit (found by review; the edit task is mechanical): L31, L44, L52, L56 (animation, taps, back, reduce-motion); L54 (hint placement + persistence rule); L24/L44/L50 (long-press, cancel paths); L36/L58/L81 (re-login); L37/L64 (decision 8 wording); L63, L66 (items 7-8).

## Global Constraints

- Hive-first, Riverpod only; no widget touches Hive: the flag goes through `lib/features/train/services/swap_move_hint.dart` → `MigratedKey` (spec §5).
- Wardroom tokens (`AppColors`), `AppTypography` only; no raw `GoogleFonts.getFont` (Gate 37); dark theme only. Do not modify `plan_generator.dart` (§4.4 r14).
- **No commit and no push in this plan.** Commit only when the founder says "commit", then only via `sh scripts/safe_commit.sh "<ONE message>"`. Never `--no-verify`.
- Mutation checks use a **file backup, never `git checkout --`**: copy to the session scratchpad, mutate, run, copy back, `diff` against the backup must be empty.
- Run on the founder's Windows machine: `flutter test <file>` (no `TZ=` prefix). State which suites actually ran.
- Source-grep tests prove PRESENCE only; behaviour is proven by the pure/controller/notifier/widget tests. Screen wiring that cannot be pumped is covered by presence pins plus the Task 7 device checklist, and the plan says so.
- Exact values: flag key `has_seen_swap_move_hint`; UNDO window 5 s; target pulse 1.7 s; moved-card highlight 400 ms; icon visible 30 dp, hit box ≥44 dp; semantic labels "Swap exercise" / "Move exercise"; tags "MOVE HERE" / "MOVING"; snackbar "Moved “<name>” to position <n>"; hint copy "On every exercise" / "Swap — use a different exercise" / "Move — change its place in today's order" / "Got it".
- **Review tier:** `user_config_migrator.dart` and `train_provider.dart` make this an account-tier (`docs/blast_radius.yaml`), tier-L batch: it needs the plan-review record (`docs/plan-reviews/<branch>.md`, `bpass: accepted`) and a self-initiated `/code-review` B-pass before any merge to `main` (CLAUDE.md §4.3, §4.12.3). The `analysis_options.yaml` rule `unawaited_futures` is a warning that aborts pre-push: wrap fire-and-forget futures in `unawaited(...)`.
- Reduce motion: the repo has no precedent (`grep -rniE "disableAnimations|reduce.?motion" lib` is empty). Add one tiny private helper `bool _motionReduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);` in `exercise_card.dart` and use it for both the glow and the ring.

## Review Focus (each line has its test in the owning task)

1. A partly-logged exercise moves: its checked sets, warm-up flags and typed values follow it (T1).
2. Duplicate exercise names (OI-358): move math is index-based; the two same-name exercises differ in `sets` so a name-based implementation fails (T1).
3. UNDO after the moved exercise was completed or moved again does nothing; UNDO **still works when a done exercise sits in the vacated slot** (T1, T4).
4. A move during `completeWorkout`'s async save is refused (`_completing`), as `unlogSets` does (T1).
5. Move mode and superset-grouping mode never overlap, and a move never leaves a stale `supersetGroupingSourceIndex` (T1, T4).
6. A swap-UNDO snackbar from before the move can never fire after it (T6 wiring + device checklist).
7. Hint: never with <2 not-done exercises, after any checked set (warm-ups included), when seen, or dismissed this session; dismissal persists once, not on every rebuild (T3, T4).
8. Reduce-motion users get no running animation on targets or rings; header fits at 360 dp wide (T5).

## File structure

| File | Responsibility |
|---|---|
| Create `lib/features/train/services/exercise_move_logic.dart` | `MoveRole`, eligibility, targets, slide + remap, undo validity |
| Create `lib/features/train/services/move_mode_controller.dart` | `MoveModeController`, `MovePlacement`: move-mode state, placement/undo and hint decisions (tap routing by role lives in the card, Task 5) |
| Create `lib/features/train/services/superset_persist_logic.dart` | Pure identity-matched superset write |
| Create `lib/features/train/services/swap_move_hint.dart` | Flag key, read/write through `MigratedKey`, `shouldShowSwapMoveHint` |
| Modify `lib/features/train/providers/train_provider.dart` | `ExerciseMoveResult`, `ActiveWorkoutNotifier.applyExerciseMove`; `swapExercise` keeps the slot's group; `_persistSupersetGroups` via the pure function |
| Modify `…/active_workout/exercise_card.dart` | Icon row, move-mode props and visuals, ticker, hint ring, extended test host |
| Modify `…/active_workout/screen.dart` | Thin wiring: controller field, `initState`, hint child, `PopScope`, snackbar, focus reset |
| Modify `lib/core/services/user_config_migrator.dart` | Register the flag in `userScopedKeys` |
| Modify docs | `lib/features/train/CLAUDE.md`, `docs/sot_registry.yaml`, `docs/naming_conventions.md`, the spec (Task 7) |

**Rebased 2026-10-21 onto `origin/main` 5f5160bf** (includes PR #135 "one LOG per exercise goes live", a0bcf802, ~800 lines in `train_provider.dart`, `exercise_card.dart`, `screen.dart`, `log_exercise_logic.dart`). What it changes for this plan:
- NEW index-keyed state `ActiveWorkoutData.suggestedInputs` (`Set<String>`, keys `'$ex-$set-$field'`, built by `suggestedKey` in `log_exercise_logic.dart`): a move MUST remap its exercise part and keep set + field, exactly as `removeExercise` now does. It joins `ExerciseMoveResult` (Task 1).
- `reopenedExercises` (`Set<String>` of NAMES) is not index-keyed: a move leaves it untouched (test asserts it).
- LOG mode is now ON by default (`LogExerciseFlags.logExerciseButtonEnabled` reads ON unless a stored `false`); the OFF path stays until OI-362. The "both LOG modes" tests still apply.
- RE-OPEN (`_onReopenExercise`, screen) makes a logged exercise not-done again, so it becomes movable; no extra handling.
- `completeWorkout` now resets `_completing` on a failed save; the `_completing` guard plan is unchanged.
- Every line number below in Tasks 5-7 was measured at a909cdb3: re-locate by symbol, not by line.

**Before Task 1:** `git fetch origin main`, then `git log HEAD..origin/main --oneline -- lib/features/train lib/core/services/user_config_migrator.dart docs/sot_registry.yaml`. OI-356/357 (LOG batch 3) also edit this area. If anything is listed, merge `origin/main` into the branch and re-read the touched files; if a once-only-hint helper now exists, Task 3 reuses it.

---

### Task 1: Pure move logic + notifier apply

**Files:**
- Create: `lib/features/train/services/exercise_move_logic.dart`
- Modify: `train_provider.dart` — add `ExerciseMoveResult` next to `ActiveWorkoutData`; add `applyExerciseMove` on `ActiveWorkoutNotifier` next to `removeExercise` (~L1648, whose remap loop is the precedent)
- Test: `test/contracts/active_workout_exercise_order_behavioral_test.dart` (copy `_SeededNotifier`, `ex(name,{sets,type,group})`, `containerWith` from `test/contracts/active_workout_set_logging_behavioral_test.dart:17-43`; the `_completing` test mirrors that file's `unlogSets` one at ~L400-414)

**Interfaces — produces:**
- In `train_provider.dart`: `class ExerciseMoveResult { const ExerciseMoveResult({required this.exercises, required this.checkedSets, required this.warmUpSets, required this.setInputValues, required this.suggestedInputs}); }` (fields typed as `ActiveWorkoutData`'s).
  `bool ActiveWorkoutNotifier.applyExerciseMove(ExerciseMoveResult r)` — one state change replacing the five fields (`reopenedExercises` untouched) **and** setting `supersetGroupingSourceIndex` to null **and** `isSupersetGroupMode` to false (so a UNDO tapped during grouping mode cannot leave group mode on with no source); returns false (state untouched) if `r.exercises.length != state.exercises.length`, or `_completing || state.isSaved || state.isComplete`.
- In `exercise_move_logic.dart`:
  `enum MoveRole { none, source, target }`
  `bool canMoveExercise(ActiveWorkoutData d, int i)` — in range and `!d.isExerciseDone(i)`.
  `bool hasMoveCandidates(ActiveWorkoutData d)` — ≥2 movable exercises.
  `List<int> moveTargets(ActiveWorkoutData d, int from)` — other movable indices ascending; empty if `from` not movable.
  `MoveRole moveRoleFor(ActiveWorkoutData d, int? sourceIndex, int i)` — tolerates a stale `sourceIndex >= length` (⇒ `none`).
  `ExerciseMoveResult? moveExerciseInSession(ActiveWorkoutData d, {required int from, required int to, bool requireMovable = true})` — null when `from == to` or either index is out of range; when `requireMovable` is true it is also null if `from` or `to` is not movable. `requireMovable: false` skips both movability checks and exists ONLY for the undo inverse (the exercise displaced into the vacated slot may be done). Slide: remove at `from`, insert at `to` (mover ends at index `to`). Remap every `"<i>-<set>"` key of the three maps, and the exercise part of every `"<i>-<set>-<field>"` key of `suggestedInputs` (set and field kept; keys that do not split into 3 parts are dropped, as `removeExercise` does), by the same permutation (`i==from → to`; `from<to`: `from<i<=to → i-1`; `from>to`: `to<=i<from → i+1`).
  `bool moveUndoApplicable(ActiveWorkoutData d, {required String exerciseName, required int movedTo})` — range-check first, then `d.exercises[movedTo].name == exerciseName && !d.isExerciseDone(movedTo)`.

- [ ] **Step 1: Write the failing tests** (`group('exercise move (pure)')`, `group('applyExerciseMove (notifier)')`):
  - slide up `[A,B,C,D]` 3→1 ⇒ `[A,D,B,C]`; slide down 0→2 ⇒ `[B,C,A,D]`; adjacent 2→1 ⇒ `[A,C,B,D]`.
  - null for `from==to`, out of range, done mover, done target (default flag).
  - set state follows (partly logged): exercise 3 has `'3-0'` checked, `'3-1'` warm-up, typed values at `'3-0'`; exercise 1 has `'1-0'` checked; move 3→1 ⇒ `checkedSets` has `'1-0'` and `'2-0'` and no `'3-*'`; `warmUpSets` has `'1-1'`; `setInputValues['1-0']` is the original object; `suggestedInputs` `{'3-0-weight','1-2-duration'}` becomes `{'1-0-weight','2-2-duration'}`; `reopenedExercises` is identical.
  - done exercise in between keeps relative order: `[A,B(done),C,D]` 3→0 ⇒ `[D,A,B,C]`, B's keys become `'2-*'`.
  - superset tag travels, partner untouched: `[Bench,Incline(g0),OHP,Row(g0)]` 3→1 ⇒ `[Bench,Row,Incline,OHP]`, Row and Incline `supersetGroup==0`, OHP null.
  - duplicate names by index: `[A(sets 3),A(sets 4),B]` 2→0 ⇒ `[B,A(3),A(4)]` in that order and `'0-0'` (was on the first A) is now `'1-0'`.
  - `moveTargets` excludes done and the mover; `hasMoveCandidates` false with <2 not-done; `moveRoleFor` with stale source ⇒ `none`.
  - undo is the inverse: apply 3→1, then `moveExerciseInSession(…, from:1, to:3, requireMovable:false)` ⇒ original exercises and maps (deep equality).
  - **undo with a done exercise displaced** (both directions): `[A,B,C(done),D]` D 3→1 then the inverse with `requireMovable:false` restores; the same inverse with the default flag returns null (pins why the flag exists). Same for `[A,B(done),C]` A 0→2.
  - `moveUndoApplicable`: false when the mover is now done; false when another exercise sits at `movedTo`; false for `movedTo` out of range (no throw).
  - Notifier: `applyExerciseMove` produces exactly one state change (listener counter 1); rejects a wrong-length result; **rejects while `_completing`** (drive a `completeWorkout` that is mid-save per the `unlogSets` test's technique; state identical); clears group mode (seed `isSupersetGroupMode: true` with a non-null `supersetGroupingSourceIndex`; after the move both are cleared); **session-only**: with a seeded `schedule_<date>` row the stored `exercises` order is byte-identical after the move.
- [ ] **Step 2:** `flutter test test/contracts/active_workout_exercise_order_behavioral_test.dart`. Expected: FAIL (symbols undefined).
- [ ] **Step 3:** Implement the types, functions and notifier method above (pure functions in the new file; the provider defines `ExerciseMoveResult` and `applyExerciseMove` itself).
- [ ] **Step 4:** Same command. Expected: all PASS.
- [ ] **Step 5: Mutate twice:** back up `exercise_move_logic.dart`; (a) delete the `warmUpSets` remap, (b) separately, delete the `suggestedInputs` remap; each time expect "set state follows" RED (the "undo is the inverse" round trip is blind to a missing remap by construction — a non-remapped move followed by its non-remapped inverse is still the identity; measured 2026-10-21: both mutations reddened exactly 1 test, "set state follows"); restore; `diff` empty; re-run PASS.

### Task 2: Superset persistence by identity + swap keeps the slot's group

**Files:**
- Create: `lib/features/train/services/superset_persist_logic.dart`
- Modify: `train_provider.dart` — `_persistSupersetGroups` (~L1805): build the identity list from `exercises`, call the pure function on `storedExercises`, keep the existing `upsertScheduled(source: WriteSource.activeWorkout)`; `swapExercise` (~L1589): the stored replacement takes `supersetGroup: newExercise.supersetGroup ?? slot.supersetGroup` on both paths: the same-logging-type path returns `newExercise` itself (~L1603), so it becomes `newExercise.copyWith(supersetGroup: () => g)` (`ExerciseData.copyWith` takes `int? Function()?`); the `resolved` constructor (~L1605-1616) gets a `supersetGroup: g` argument. (It also drops `exerciseType`/`muscleLabel` today; that is pre-existing and out of scope — OI-365 covers it.) No caller wants "ungroup via null" (callers: `swap_sheets.dart` L58, L189, L220).
- `swap_sheets.dart` is **not** edited (one writer, in the notifier).
- Test: `test/contracts/active_workout_superset_persist_behavioral_test.dart`

**Interfaces — produces:**
`typedef SessionExerciseIdentity = ({String? exerciseId, String name, int? supersetGroup});`
`List<dynamic> applySupersetGroupsByIdentity({required List<dynamic> stored, required List<SessionExerciseIdentity> session})` — returns a new list. For each session entry in order, match the first not-yet-matched stored Map row with equal identity (when both ids are non-null the ids decide — different ids never match even with equal names; otherwise `(exercise_name ?? name)` equal); write `superset_group` (null included) onto matched rows; unmatched stored rows and non-Map entries pass through untouched.

- [ ] **Step 1: Write the failing tests:**
  - unchanged order equals today's index write (stored `[a,b,c]` old groups `[5,null,7]`, session same order groups `[0,null,0]` ⇒ `[0,null,0]`).
  - reordered session `[C,A,B]` ⇒ each stored row gets its own exercise's group; id beats name; duplicate names without ids pair first-to-first; a swapped-in exercise with no stored row leaves the original row untouched; non-Map entries pass through.
  - Notifier: seed Hive `schedule_<date>` `[Bench,Incline,OHP,Row]`, `applyExerciseMove` Row 3→1, `pairSuperset` Incline+Row; poll (real zone, the write is `unawaited`) until the row for Row and Incline carry the group and OHP's is null.
  - **swap keeps the group (behavioural):** `swapExercise(i, replacementWithNullGroup)` on a slot with `supersetGroup 0` ⇒ result group 0 on BOTH paths (same logging type; different logging type); a replacement that already has a group keeps its own; swap UNDO (`swapExercise(i, original)`) restores the original's group.
  - Presence pin only: comment-stripped `swapExercise` body contains `supersetGroup` (copy `_stripComments` from `test/contracts/exlog_exercise_id_swap_threading_test.dart`).
- [ ] **Step 2:** run the new file. Expected: FAIL.
- [ ] **Step 3:** Implement. Read first and keep what they pin: `test/train/swap_logging_type_test.dart:30-46` (regex on the `swapExercise` body), `test/contracts/swap_exercise_logging_type_behavioral_test.dart`.
- [ ] **Step 4:** Run the new file plus `flutter test test/train/swap_logging_type_test.dart test/contracts/swap_exercise_logging_type_behavioral_test.dart test/contracts/exlog_exercise_id_swap_threading_test.dart test/contracts/swap_add_exercise_double_pop_behavioral_test.dart test/features/train/swap_undo_snackbar_dismisses_test.dart test/contracts/active_workout_set_logging_behavioral_test.dart test/safety/null_guard_test.dart test/contracts/equipment_needed_shape_test.dart`. Expected: PASS.
- [ ] **Step 5: Mutate twice:** (a) drop the `?? slot.supersetGroup` ⇒ "swap keeps the group" RED; (b) revert `_persistSupersetGroups` to index writing ⇒ reordered/notifier tests RED.

### Task 3: First-use hint flag (per account, local)

**Files:**
- Create: `lib/features/train/services/swap_move_hint.dart`
- Modify: `lib/core/services/user_config_migrator.dart` (`userScopedKeys`, one comment line: per-account, never cloud)
- Test: `test/contracts/swap_move_hint_flag_behavioral_test.dart` (pattern: `test/contracts/measurement_sign_out_lifecycle_test.dart:56-70`, incl. its write-and-read-back precondition)

**Interfaces — produces:**
`const String kSwapMoveHintSeenKey = 'has_seen_swap_move_hint';`
`bool swapMoveHintSeen()`; `Future<void> markSwapMoveHintSeen()` — both call `MigratedKey` with the **string literal** `'has_seen_swap_move_hint'` (not the constant), so the `migrated_key_contracts_test.dart:33-44` literal scan covers the key.
`bool shouldShowSwapMoveHint({required bool seen, required bool dismissedThisSession, required ActiveWorkoutData data})` — `!seen && !dismissedThisSession && hasMoveCandidates(data) && data.checkedSets.isEmpty && !data.isSupersetGroupMode && !data.isSaved` (warm-ups count as logged; no hint while ⇅ itself is hidden).
Neither is a query-named writer (`cqrs_query_naming_lib.dart:90`): the write lives only in `markSwapMoveHintSeen`.

- [ ] **Step 1: Write the failing tests:** key in `UserConfigMigrator.userScopedKeys`; after `markSwapMoveHintSeen()` the value is in `userBox` and absent from `configBox` (read it back first so absence is not vacuous); after `UserRepository.clearAllData()` it is gone; truth table of `shouldShowSwapMoveHint`: seen ⇒ false; dismissed ⇒ false; one not-done ⇒ false; two not-done, nothing checked ⇒ true; **one warm-up set checked ⇒ false**; group mode on ⇒ false; `isSaved` ⇒ false. The "one not-done" row uses a single-exercise fixture (so it isolates `hasMoveCandidates`, not `checkedSets`).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement; add the key to `userScopedKeys`.
- [ ] **Step 4:** Run the new file plus `test/contracts/user_scoped_hive_keys_writer_to_reader_test.dart test/contracts/user_scoped_hive_keys_behavioral_test.dart test/contracts/migrated_key_contracts_test.dart test/safety/config_to_user_migration_test.dart test/contracts/notification_prefs_rescope_behavioral_test.dart test/contracts/referral_unit_c_lifecycle_and_pins_test.dart` (paths: confirm each with `ls`; two are cited by line from `userScopedKeys` references). They assert no count (verified by two reviewers), so no expectation edits are expected; if one fails, fix the assertion, never loosen. Expected: PASS.
- [ ] **Step 5: Mutate once:** remove the key from `userScopedKeys`; expect the registration test RED.

### Task 4: MoveModeController (all screen decisions, pure)

**Files:**
- Create: `lib/features/train/services/move_mode_controller.dart`
- Test: `test/contracts/move_mode_controller_behavioral_test.dart`

**Interfaces — produces:**
`class MovePlacement { final ExerciseMoveResult result; final String exerciseName; final int from; final int to; }`
`class MoveModeController { MoveModeController({required bool hintSeen});`
- `int? get sourceIndex; bool get active;`
- `bool enter(ActiveWorkoutData d, int index)` — false (no change) if `!canMoveExercise`, `!hasMoveCandidates`, or `d.isSupersetGroupMode`; else sets the source and returns true. Calling it on the current source toggles off (returns false, `active` false).
- `void cancel()`.
- `MovePlacement? place(ActiveWorkoutData d, int target)` — builds via `moveExerciseInSession`; clears the source in every case; null if the move is invalid.
- `ExerciseMoveResult? undo(ActiveWorkoutData d, MovePlacement p)` — null unless `moveUndoApplicable(d, exerciseName: p.exerciseName, movedTo: p.to)`; else `moveExerciseInSession(d, from: p.to, to: p.from, requireMovable: false)`.
- `bool showHint(ActiveWorkoutData d)` ⇒ `r = !active && shouldShowSwapMoveHint(seen: _hintSeen, dismissedThisSession: _hintDismissed, data: d)`; when `r` is true also sets `_hintWasShown = true` (plain Dart state, safe to set during `build`); returns `r`.
- `bool dismissHint()` — `if (_hintSeen || _hintDismissed) return false;` otherwise sets both and returns true; the caller persists with `unawaited(markSwapMoveHintSeen())` on true. Repeated calls from rebuilds, and every call when constructed with `hintSeen: true`, are no-ops.
- `bool shouldDismissHintOnData(ActiveWorkoutData d)` ⇒ `!_hintSeen && !_hintDismissed && _hintWasShown && d.checkedSets.isNotEmpty` (the hint is only retired after it was actually visible; the explicit "Got it"/icon-tap paths call `dismissHint()` directly and are fine without it, because the user found the icons).

- [ ] **Step 1: Write the failing tests:** `enter` rejects done / last-candidate / group-mode and toggles on the source; `place` happy path returns a correct `MovePlacement` and clears the source; invalid place clears the source and returns null; `undo` restores exactly (deep equality), including with a done exercise in the vacated slot; `undo` null after the moved exercise is completed or another exercise sits at `movedTo`; `undo` after an edit to a slot OUTSIDE the [to..from] range leaves that slot and its set maps byte-identical (slots inside the range shift by one with their maps remapped to match); `showHint` false while active; `dismissHint` true once then false, and always false when constructed with `hintSeen: true`; `shouldDismissHintOnData` true only after `showHint` returned true at least once AND a warm-up is checked, false if the hint was never shown (one-exercise day), false once dismissed; `enter` on a different index while active is unreachable from the UI (documented), but `enter` on the current source toggles off.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement. **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Mutate once:** make `undo` use the default `requireMovable` ⇒ the displaced-done test goes RED; restore; `diff` empty.

### Task 5: Card header icons, move visuals, reduce motion

**Files:**
- Modify: `exercise_card.dart` — chip block (`:962-968`, chevron `:952-982`), constructor (`:23-66`), header `GestureDetector` (`:892-895`), `debugExerciseCardHostForTest` (`:1390`); add a `TickerProviderStateMixin` to `_ExerciseCardState` (it has none today)
- Test: `test/features/train/swap_move_icons_widget_test.dart` (follow the ORDER and real-IO notes in `test/features/train/log_exercise/harness_spike_test.dart`)

**Interfaces:**
- Consumes: `MoveRole` (Task 1).
- Produces on `_ExerciseCard`: `final bool moveModeActive; final MoveRole moveRole; final bool moveTargetAbove; final bool canMove; final VoidCallback onMove; final VoidCallback onMoveHere; final bool showHintRing; final bool justMoved;` — the bools/role have defaults (`false`/`MoveRole.none`); `onMove` and `onMoveHere` are `required` (a const `VoidCallback` has no default), and `debugExerciseCardHostForTest` supplies `() {}` for them. The host gains optional pass-throughs of all of these plus `onSwap`, `onFocus`, and a new pump helper (the existing `pumpCard` in `card_harness.dart` takes none of them). `onLongPressHeader` stays a required `VoidCallback`; the suppression is card-side only (header `onLongPress: moveModeActive ? null : widget.onLongPressHeader`).
- Behaviour, per role (the table is exhaustive; nothing else is rendered or tappable in move mode):
  | Role | ⇄ | ⇅ | pill | header body tap | done-chip tap | plate tap |
  |---|---|---|---|---|---|---|
  | normal (no move mode), not done | yes (`onSwap`) | yes if `canMove` (`onMove`) | – | `onFocus` | – | plate sheet |
  | normal, done | – | – | `✓ DONE` chip (`onFocus`) | `onFocus` | `onFocus` | plate sheet |
  | move mode, source | yes (`onSwap`) | filled (`onMove` = cancel) | "MOVING" | `onMove` (cancel) | – | **null** |
  | move mode, target | – | – | "↑/↓ MOVE HERE" (`onMoveHere`) | `onMoveHere` | – | **null** |
  | move mode, done | – | – | `✓ DONE` chip, **tap null** | none | none | **null** |
  | move mode, role none but not done (stale source index only) | – | – | – | none | – | **null** (inert; the screen never produces it) |
  Glyphs: ⇄ = `Icons.swap_horiz`, ⇅ = `Icons.swap_vert`; "filled" = gold-filled circle behind the glyph.
  Each icon: 30 dp circle in a 44 dp hit box, `Semantics(button:true,label:)`, `Tooltip(excludeFromSemantics: true)`. Target: dashed border via the existing `WardDashedBorder` (`lib/shared/widgets/wardroom/ward_dashed_border.dart`; never both `color:` and `decoration:` on one `Container`), 1.7 s glow. Done in move mode: opacity 0.5. `moveTargetAbove` is set by the screen as `sourceIndex != null && i < sourceIndex`; arrow "↑" when true else "↓".
  - `showHintRing` ⇒ gold ring around both icons; `justMoved` ⇒ gold border via `AnimatedContainer(duration: _motionReduced ? Duration.zero : 400 ms)` (fades in 400 ms; the screen clears the flag at 1000 ms so it fades out 400 ms: about 1.4 s total). It is keyed by exercise name, so with OI-358 duplicate names both cards would highlight (cosmetic, accepted).
  - Reduce motion: `_motionReduced(context)` is read in `build`; the repeating controller is started/stopped in `didChangeDependencies` and when role/`showHintRing` change (a controller created once in `initState` would keep repeating). Reduced ⇒ glow/ring static, highlight a plain border.
  - Narrow width: the name column takes the leftover space with ellipsis (≈134 dp at 360 dp; a 30-char name wraps, never overflows).
  - Do not put `${exerciseIndex + 1}` / `${index + 1}` in `exercise_card.dart` (`exercise_plate_badge_sites_test.dart` forbids it); the snackbar's `to + 1` lives in `screen.dart`. Keep `ExercisePlateThumb` and `ExercisePlateSheet.show` in the file.

- [ ] **Step 1: Write the failing widget tests** (tests using `find.bySemanticsLabel` wrap in `final h = tester.ensureSemantics(); … h.dispose();`): icons found by semantics label (exactly one each — guards the Tooltip/Semantics duplicate risk); no `⇄ SWAP` text; taps call `onSwap`/`onMove`; `canMove:false` hides move; done card shows `✓ DONE` only; **one test per table row**: a target has no `Icons.swap_horiz` and no `Icons.swap_vert`, a header tap calls `onMoveHere` but NOT `onFocus`, a plate tap opens no sheet; the source shows ⇄ + filled ⇅ + MOVING, its header tap calls `onMove`; a done card in move mode is dimmed (opacity 0.5) and tapping `find.text('✓ DONE')`, the header, and the plate calls nothing (`onFocus` count 0, no sheet); long-press in move mode calls nothing; both LOG modes (`onLogExercise` null / non-null) render the icons; with `disableAnimations:true` a target card leaves `tester.binding.transientCallbackCount` equal to the same card with `moveRole: none` (the baseline may be 0; never `pumpAndSettle` on the non-reduced path, the pulse repeats forever), and without it the count is greater; **at 360 dp (a `SizedBox(width: 360)` around `debugExerciseCardHostForTest(isExpanded: false, …)`) a 30-char exercise name with the MOVE HERE pill pumps with no overflow exception**.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement (pills use `WardChip` wrapped in a `GestureDetector`; `WardChip` has no `onTap`).
- [ ] **Step 4:** Run the file, then `flutter test test/features/train test/train test/contracts/exercise_plate_badge_sites_test.dart test/contracts/readiness_checkin_behavioral_test.dart test/contracts/rep_input_validation_test.dart`. Expected: PASS.
- [ ] **Step 5: Mutate once:** render the move icon regardless of `canMove` ⇒ hide test RED; restore with `diff` empty.

### Task 6: Screen wiring (thin shell)

**Files:**
- Modify: `screen.dart` — state ~L64-95 (add `initState`, which does not exist today), `_isExerciseExpanded` (L222), `ref.listen` on `isComplete` (L270), live `Scaffold` return (L328), card call site (L484-567)
- Test: `test/contracts/swap_move_screen_wiring_test.dart` (presence pins on comment-stripped source). The real screen is not pumpable (`swap_undo_snackbar_dismisses_test.dart:22-31`), so every *decision* is already proven in Tasks 1-5 and this task proves only that the shell calls them; the rest is the Task 7 device checklist.

**Interfaces — consumes:** Tasks 1-5.

- [ ] **Step 1: Implement, in this order:**
  1. `late final MoveModeController _move;` created in a new `initState` with `hintSeen: swapMoveHintSeen()`. `Timer? _justMovedTimer; String? _justMovedName;`.
  2. `_isExerciseExpanded` returns false while `_move.active`. `_focusedExerciseIndex` is never written by enter/cancel.
  3. Card call site: `moveModeActive: _move.active`, `moveRole: moveRoleFor(data, _move.sourceIndex, i)`, `moveTargetAbove: _move.sourceIndex != null && i < _move.sourceIndex!`, `canMove: hasMoveCandidates(data) && canMoveExercise(data, i) && !data.isSupersetGroupMode && !data.isSaved && !ref.read(activeWorkoutProvider.notifier).isCompleting` (review mode and the save window show no ⇅), `onMove: () { _dismissHintAndPersist(); setState(() => _move.enter(ref.read(activeWorkoutProvider), exIdx)); }` (toggles off on the source; the loop variable at the call site is `exIdx`, and `onSwap` reuses the same `exIdx` closure — read `i` above as `exIdx`), `onMoveHere: () => _completeMove(i)`, `onSwap: () { _dismissHintAndPersist(); setState(_move.cancel); _showSwapSheet(...); }`, `onLongPressHeader` **unchanged** (the card suppresses it in move mode), `showHintRing: _move.showHint(data) && i == 0`, `justMoved: name == _justMovedName`. The card itself routes header taps by role (Task 5), so `onFocus` stays as it is.
  4. `_completeMove(int target)` (no `data` parameter; read `ref.read(activeWorkoutProvider)` at tap time — the build-captured `data` can be up to a frame stale and `applyExerciseMove` replaces whole maps): `final p = _move.place(d, target)`; null ⇒ `setState(() {})` and return. Else `final ok = ref.read(activeWorkoutProvider.notifier).applyExerciseMove(p.result)`. If `!ok` (saving, review mode, wrong length) ⇒ `setState(() {})` and return with no toast (existing snackbars untouched). If ok, **in the same synchronous event** `final m = ScaffoldMessenger.of(context); m.hideCurrentSnackBar();` (this also clears the unstored 3 s warm-up toast and a stale index-keyed swap UNDO, `swap_sheets.dart:203-225`, which a plain `_dismissSwapUndoSnackBar()` would miss when `_swapUndoMessenger` is null; no frame renders between apply and hide, so the stale UNDO cannot be tapped), then `setState(() { _focusedExerciseIndex = null; _justMovedName = p.exerciseName; })`, `_clearLogUndo()` (index-keyed LOG undo), restart `_justMovedTimer` (1000 ms, callback checks `mounted`, clears `_justMovedName` via `setState`), then `m.showSnackBar(...)` the 5 s "Moved “<name>” to position <to+1>" with UNDO and store `_swapUndoMessenger = m` so completion/dispose dismissal covers it. UNDO: `if (!mounted) return; final r = _move.undo(ref.read(activeWorkoutProvider), p); if (r != null && ref.read(activeWorkoutProvider.notifier).applyExerciseMove(r)) { _clearLogUndo(); setState(() => _focusedExerciseIndex = null); }` (the stale-read concern is at most one frame, since the screen watches the provider; reading at tap time is still the rule). After a move nothing scrolls: the mover lands next to the tapped target, which is on screen.
  5. Hint bar while `_move.active`: "Tap where *<name>* goes" + Cancel (model: the superset chip at screen.dart L367-399).
  6. Hint callout: its own `ListView` child (`ValueKey('swap_move_hint')`) placed **after** the warm-up section (`_WarmupCooldownSection`, an unkeyed first child — inserting before it would recreate its State) and **before** the card entries, shown while `_move.showHint(data)`; copy per Global Constraints. "Got it" (wrapped in `setState`), the first tap of either icon (steps 3), and (registered in `build` via `WidgetsBinding.instance.addPostFrameCallback`, callback starts with `if (!mounted) return;`, only scheduled when `_move.shouldDismissHintOnData(data)`) the first checked set call `_dismissHintAndPersist()` = `if (_move.dismissHint()) unawaited(markSwapMoveHintSeen());`. The icon-tap path is fine even if the hint was not visible: the user found the icons.
  7. `PopScope(canPop: !_move.active, onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(_move.cancel); })` wrapping **only the live `Scaffold`** (L328); the earlier no-workout (L280) and complete (L319) branches stay unwrapped.
  8. In the existing `ref.listen` on `isComplete`: add one plain statement `_move.cancel();` after `_dismissSwapUndoSnackBar();`. Keep every existing statement; no closure or `setState` inside, because `swap_undo_snackbar_dismisses_test.dart:282-290` matches that block with a lazy regex ending at the first `});`. `dispose` cancels `_justMovedTimer`.
- [ ] **Step 2:** Write the presence pins (screen source, comments stripped): constructs `MoveModeController`; `_clearLogUndo()` inside `_completeMove`; `PopScope(`; `canPop: !_move.active`; `hideCurrentSnackBar()` appears in `_completeMove` after the `applyExerciseMove(` call and its `!ok` early return; the return value of `applyExerciseMove` is used; `unawaited(markSwapMoveHintSeen())`; the callout sits outside the card's `Column(key: _exerciseKeys[...]`; the `isComplete` listen block contains `_move.cancel();`. Run: FAIL, then after Step 1 PASS.
- [ ] **Step 3:** `flutter analyze lib/` (the screen is a library with `part` files: analyse `lib/`, not the single file). Expected: no issues in touched files.
- [ ] **Step 4:** Run `flutter test test/contracts/active_workout_set_logging_behavioral_test.dart test/contracts/swap_undo_snackbar_modal_pop_test.dart test/features/train/swap_undo_snackbar_dismisses_test.dart test/contracts/swap_add_exercise_double_pop_behavioral_test.dart test/train/exercise_card_weight_display_format_test.dart test/features/train`. (`active_workout_set_logging_behavioral_test.dart:417-560` pins `screen.dart` source: `_logUndo = null;` in the listen block, `onComplete: _clearLogUndo`, `onLogExercise: logMode`, `logMode` read once per build — keep all four.) Expected: PASS.
- [ ] **Step 5: Mutate once:** delete the `hideCurrentSnackBar()` call from `_completeMove` ⇒ the presence pin goes RED; restore with `diff` empty. (Screen behaviour beyond presence is covered by the Task 7 device checklist, said plainly.)

### Task 7: Docs, contracts, gate loop, device checklist

**Files:**
- Modify: `lib/features/train/CLAUDE.md` (row `active_workout_exercise_order`: session-only; writer `applyExerciseMove` fed by `moveExerciseInSession`; remap invariant incl. `supersetGroupingSourceIndex` cleared; superset persisted by identity; swap keeps the slot's group; keep growth to ≈1-2 KB: the file is 19,508 B vs a recorded 18,036 B, soft band 15%)
- Modify: `docs/sot_registry.yaml` — **first re-measure every `line_range` that cites `train_provider.dart` or `exercise_card.dart`** (`completedSets` 1327-1329, `isExerciseDone` 1357-1364, `liveVolumeKg` 1380-1389, `toggleSet` 1508-1517, `logSets` 1524-1539, `unlogSets` 1546-1563, `recordSetValues` 1566-1571, `TemplatesNotifier` 2295-2311 (a different concept; 2313-2326 is a prose entry that cannot go stale), `completeWorkout` 1762-2098, `_onFieldChanged` 388-398, `_mirrorFrom` 431-462, `_onLogPressed` 481-506, and any others the gate reports), because `check_sot_registry_parity.dart` errors `[stale-line-range]`; **then** add the concept `active_workout_exercise_order` (copy the shape of `active_workout_set_logging`, `behavioral_test_path: test/contracts/active_workout_exercise_order_behavioral_test.dart`)
- Modify: `docs/naming_conventions.md` §3.3 (key row; literal-key precedent at ~L98) **and** §8 glossary (new terms "move mode", "MOVING", beside the existing "day swap" row at ~L298, cross-referencing it: that row's NOT-cell already says a day swap is not an exercise swap; the day-swap tag itself is `DaySwapCopy.movedTag`). Re-measure the SoT ranges after ALL code tasks are done (Task 2 also edits `train_provider.dart`); register the new concept last.
- Modify: the spec — apply the nine "Spec amendments" above at the listed lines
- The new SoT concept is a NEW row in the nested CLAUDE.md's "SoT concepts owned here" table (neighbour: `active_workout_set_logging`); if the budget gate's soft band warns, `--record` is allowed.

- [ ] **Step 1:** Make the edits. Read each validator first: `scripts/check_nested_claude_md_content.dart`, `scripts/check_sot_registry_parity.dart`, `scripts/check_sot_behavioral_test_paths.dart`; run `dart run scripts/check_context_artifact_budget.dart` (re-record with `--record` only if the drift is intended).
- [ ] **Step 2: Full gate loop (§4.12.8), before any review dispatch:** `flutter analyze lib/`; the complete `flutter test`; `sh scripts/pre-commit.sh` (nothing is committed; it proves the gates). Report the scope literally: which suites ran, how many passed.
- [ ] **Step 3: Device/web checklist for the founder** (not automatable): ⇄ opens the swap sheet as before incl. ADD/REMOVE; ⇅ enters move mode, targets pulse, done cards dim and ignore taps; tapping a target header places; tapping the moving card cancels; others keep their order, UNDO restores; Cancel / ⇅ again / system back leave and the previously open card returns; header back arrow leaves the screen; swapping a superset member keeps the bar pair; a plan-generated superset member moves alone and its partner still expands with it; swap then move within 5 s: the swap UNDO is gone; first workout shows the hint once above the first card and typing in that card is not interrupted when it disappears; never again after Got it / first set; a second account on the same phone sees it again; finishing in move mode ends cleanly; OS "remove animations" stops the pulse; 360 dp-wide phone shows no overflow.

## Self-review

- **Spec coverage:** decisions 1-9 → T5/T6 (icons, flow), T1 (slide, session-only), T3 (hint, per-account), none for no-switch/no-profile-entry; §5 behaviours → T5/T6 with the amendments for animation, hint placement, tap rules; §6 alignment → T1 (maps, duplicates, grouping index, `_completing`), T2 (persist, swap group), T6 (focus, LOG undo, stale swap snackbar); builder-check items → T1/T4/T5; board links OI-357/358/365 → "Before Task 1".
- **Review round 3 (no blockers; plan-text only) folded in:** highlight timing made single-valued, false undo-test wording replaced, dead tap-routing API removed from the controller, hide-snackbar moved after a successful apply, hint also gated on group mode / review mode, post-frame dismissal location, stale-source table row, glyphs named, `exIdx`.
- **Review round 2 folded in:** `unawaited`, suppression card-side only (the controller's long-press helper dropped, the card prop type unchanged), review-mode/save-window guards + `applyExerciseMove` return value, group-mode cleared on apply, per-role icon table (inert chip/plate in move mode), hint burned-before-shown fixed (`_hintWasShown`), `hideCurrentSnackBar` via messenger, stale-`data` fix, hint after warm-up section, `didChangeDependencies` motion handling, `WardDashedBorder`, plate-badge test constraint, `ensureSemantics`, `transientCallbackCount`, 360 dp helper, required callbacks, spec amendments 7-9 with line numbers.
- **Review round 1 folded in:** undo inverse (flag + tests), `_completing`, `supersetGroupingSourceIndex`, move-mode taps, stale swap-UNDO snackbar, hint-callout State loss, hint repeat-persist, warm-up vs `completedSets`, animations amended, screen testability via controller, SoT line ranges, test lists, `_clearLogUndo`, `initState`, naming §8, reduce-motion precedent, narrow-width test, Tooltip semantics, header-back choice, same-account re-login, swap carries group in the notifier (behavioural) instead of the sheets (presence).
- **Types:** `ExerciseMoveResult`, `MoveRole`, `moveExerciseInSession(..., requireMovable)`, `moveUndoApplicable`, `MoveModeController`, `MovePlacement`, `SessionExerciseIdentity`, `applySupersetGroupsByIdentity`, `shouldShowSwapMoveHint` are named identically wherever used.
- **Proportion:** signatures, test names with assertions, locations; no bodies.
