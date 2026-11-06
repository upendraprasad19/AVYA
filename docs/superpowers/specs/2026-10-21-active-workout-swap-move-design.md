# Active workout: ⇄ swap + ⇅ move, and weekday exercise swap — design

Status: written 2026-10-21, awaiting founder read. Not built. Not committed.
Baseline: `origin/main` @ `a909cdb3`. Every file and line cited below was read at `7cfa485e` and re-checked identical at `a909cdb3` (no diff in `lib/features/train`, `swap_service.dart`, `workout_write_service.dart`, `user_config_migrator.dart`, wardroom primitives).
Mockups (HTML, open in a browser): `docs/mockups/2026-10-21-exercise-swap-and-move-icons-v4.html` (Unit 1, final), `docs/mockups/2026-10-20-exercise-swap-planned-and-in-workout-v1.html` (Part 2 = Unit 2 proposal; Part 1 is the as-built in-workout swap). `mockups/` is gitignored by repo convention (`.gitignore:120`, no mockup is tracked), so these files exist only in this worktree; this document is written to be self-contained without them.

Marking: **[F]** = founder decided. **[my call]** = I chose it; the founder has not confirmed it. Everything unmarked is verified fact about today's code.

## 1. Intent

A user in the middle of a Push Day finishes bench and wants the triceps exercise planned for slot 5 to come next (equipment busy, or they want to pair muscles). Today they can swap an exercise for another, but cannot change the order, and the week plan cannot be edited at all from the UI. Industry norm for mid-workout reordering is drag-and-drop (checked: Gymkee, StrengthLog, JEFIT, Fitbod); this app's founder chose a tap-to-place variant that avoids dragging with a phone on a bench.

## 2. Two separate builds [F]

- **Unit 1** — in the active-workout screen: the swap control becomes an icon, a second "move" icon is added, move mode, first-use hint. Self-contained in `lib/features/train/` plus one local flag.
- **Unit 2** — weekday exercise swap from the Train tab. Different surfaces, writes the saved plan, bigger risk. Built after Unit 1, tracked on the OI board (filed with `scripts/mint_oi.sh` when this document is committed). Same icon, same picker, same copy as Unit 1.

## 3. Unit 1 — what exists today (verified)

- Active workout screen is a plain `ListView` of exercise cards in plan order (`active_workout/screen.dart:406`). No reorder anywhere in it. The only reorder UI in the app is Template Builder's `ReorderableListView`.
- Each not-done card has a text chip `⇄ SWAP` (`exercise_card.dart:965`) → `_showSwapSheet` (`swap_sheets.dart:41`) → `ExerciseSwapSheet`. Done cards show `✓ DONE` instead.
- Swap is **session-only**: `ActiveWorkoutNotifier.swapExercise` (`train_provider.dart:1589`) changes provider state and clears that slot's set state; it does not write the saved `schedule_<date>` row.
- Long-press on a card header starts superset grouping (`onLongPressHeader`). That gesture is taken.
- `pairSuperset` (`train_provider.dart`) can group any two indices; members need **not** be adjacent. The card draws first/last-in-group from neighbours (`screen.dart` ~L440).
- Exercise rows are `Column`s keyed by a per-exercise-name `GlobalKey` (`_exerciseKeys`, `screen.dart:64,438,481`), so a card's State follows its exercise when the list order changes.
- Active-session persistence (`ActiveWorkoutPersistence`) stores only the current exercise's name and set context for the AI coach; it does not store the list. The session itself lives in a non-autoDispose provider.

## 4. Unit 1 — decisions

1. **[F]** The header's `⇄ SWAP` text chip becomes **two icon-only controls**: `⇄` (swap — behaviour unchanged) and `⇅` (move), same row, left of the chevron. Icons stay as drawn (not ▲▼).
2. **[F]** Tap `⇅` on a not-done card → that card is "moving"; every other eligible card becomes a target with a subtle pulse → tap a target → the moved exercise takes that slot.
3. **[F]** **Slide** semantics: the moved exercise lands in the target's slot and the exercises in between shift one place; everyone else keeps their relative order. (Not a pairwise trade.)
4. **[F]** **Session-only**: the new order is not saved to the day's plan, same as swap today.
5. **[F]** A first-use hint names the two icons; plus long-press tooltip; plus screen-reader labels.
6. **[F]** No "show hints again" entry in Profile.
7. **[F]** The "seen" flag is **per account, local**: stored in the account's own box, not in cloud, not device-global.
8. **[F]** **Plain ship, no kill switch.** Unit 1's only synced write is the superset-persist path, and its output is identical to today's whenever the order is unchanged and no swap/add/remove happened (after those, the identity write is *more* correct than today's index write); that equivalence is pinned by a mutation-proven test instead of a flag. *(Amended 2026-10-21 by plan review.)*
9. **[F]** Day swap and exercise swap keep the **same glyphs** (`⇄`, `⇅`) everywhere, including Unit 2. The picker's own title ("SWAP EXERCISE" vs the day picker's) is the only disambiguation.

## 5. Unit 1 — behaviour

**Header row.** `[plate][name + meta][⇄][⇅][chevron]` on every card that is not done. A done card keeps `✓ DONE` and gets neither icon. Icons draw ~30 dp, hit area ≥44 dp, with semantic labels "Swap exercise" / "Move exercise" and tooltips (long-press). `⇄` opens today's `ExerciseSwapSheet` with today's behaviour, including ADD / REMOVE.

**Move mode.** Entering: tap `⇅`. A hint bar appears under the header ("Tap where *<name>* goes", Cancel). All cards collapse to header-only (their existing collapse; no new animation) so every target is on screen. The moving card shows ⇄, a filled ⇅ and a "MOVING" tag. Each other eligible card shows a dashed gold border, a slow glow and a "MOVE HERE" tag (↑ when above the mover, ↓ when below), no icons; its WHOLE header (plate, name, chevron) places. Done cards dim and ignore every tap (chip and plate too). Header long-press (superset pairing) does nothing in move mode, and ⇅ is hidden while superset-grouping mode or review mode is on. Leaving without moving: Cancel, tap `⇅` again, tap the moving card, or system back (back cancels the mode before it leaves the screen); the header's back arrow (`context.pop()`) leaves the screen and simply ends the mode. Tapping `⇄` while in move mode cancels the mode first. The rest timer and elapsed clock are unaffected. *(Amended 2026-10-21 by plan review.)*

**A move changes exactly one exercise [my call, matches the founder's stated expectation].** Move acts on the tapped exercise only; every other exercise keeps its content and relative order. A superset tag is an attribute of the exercise row and travels with it; its partners are not moved and not touched. This is not an edge case: the plan generator pairs an exercise with a *later* antagonist without making them adjacent (`superset_pairer.dart`), so generated partners are usually apart, and the screen already handles that (bar on both, partners expand together, partner revealed after a LOG via `getSupersetPartners`, which works by group id, not adjacency). Moving up lands the exercise immediately before the target; moving down, immediately after it; ↑/↓ comes from comparing indices.

**Eligibility [my call].** An exercise can be the mover or a target only if it is not done. A partly-logged exercise is not done, so it can move. Done exercises keep their relative order and shift if they sit between source and destination. The `⇅` control is hidden when fewer than two not-done exercises exist.

**Cancel [my call].** Cancel, `⇅` again, tapping the moving card, and back leave `_focusedExerciseIndex` untouched, so the card that was expanded before the mode comes back. Move mode collapses cards through a separate screen-level flag, not by changing focus.

**After a move.** The list reorders instantly (it is a plain `ListView`; a 220 ms slide would need a different list widget; amended 2026-10-21) and the moved card gets a gold border that fades in over 400 ms, holds until 1 s, and fades out. `_focusedExerciseIndex` is cleared so the existing "first not-done is expanded" rule decides which card opens **[my call]**. A 5-second snackbar "Moved *<name>* to position *n*" with UNDO restores the previous order. Follow the existing UNDO-snackbar ownership pattern (`_swapUndoMessenger`, dismissed on workout completion and in `dispose`; history: diagnose `swap-undo-snackbar-completion-dismiss`).

**First-use hint [my call on all rules].** A small callout, no scrim, as its own list item directly above the first card (never inside a card, where removing it would rebuild the card and drop typed input; amended 2026-10-21), with a gold ring pulsing around the first card's icons: eyebrow "On every exercise", "Swap — use a different exercise", "Move — change its place in today's order", button "Got it". Shows while ≥2 exercises can move, nothing is checked yet (warm-ups count), and neither superset-grouping nor review mode is on. Dismisses on Got it, on the first tap of either icon, or automatically on the first checked set — the last only if the hint was actually shown, so a one-exercise day never burns it. Never shown again for that account until its local data is cleared (sign-out/in or reinstall clears `userBox`, so it shows once more; accepted). Draft copy; final copy to be checked against the Wardroom/Navy voice (`lib/shared/widgets/wardroom/CLAUDE.md`).

**Reduce motion.** Pulse and ring hold still; the moved card's border appears and clears without fading.

**Flag storage.** One boolean in the account's `userBox`, read/written through `MigratedKey`, registered in `UserConfigMigrator.userScopedKeys`, added to the prefix/literal registry in `docs/naming_conventions.md` §3.3 (precedent: `body_measurement_prompt_dismissed_at`). Do **not** use `configBox` (device-global: a second account on the phone would never see the hint). Key name is the builder's to choose per §3.3 (suggestion: `has_seen_swap_move_hint`). No cloud column, no sync.

## 6. Unit 1 — what the builder must keep aligned (all verified in source, none of it designed)

- **Per-slot state is keyed by position**: `checkedSets`, `warmUpSets`, `setInputValues` all use `"<exerciseIndex>-<setIndex>"`; plus `supersetGroupingSourceIndex`. A move must remap all of them in one provider method (precedent: `removeExercise` remaps the same maps). Grep every `ActiveWorkoutData` field and every `'$exerciseIndex-'`-style key construction; do not trust this list to be complete.
- **Screen-level index state**: `_focusedExerciseIndex`; the LOG-button machinery (`LogExerciseController`, `_logUndo`). The LOG UNDO record holds only `exerciseIndex`, `exerciseName`, `setIndexes`, `shownAt`, `generation` (`log_exercise_logic.dart`, `LogUndoRecord` / `undoRecordFor`; `before` is used only to work out which sets were newly checked). `visibleUndoRecord` already hides the toast when a different exercise sits at that index, and `unlogSets` refuses on a name mismatch (`train_provider.dart:1549-1552`). So a move can never restore an old order through UNDO; at worst it makes a 5-second toast disappear when it shifts the logged exercise's index. **[my call]** do not remap the record; a move CLEARS it (`_clearLogUndo()`), the safe form of "the toast disappears" (amended 2026-10-21). (An earlier draft of this document claimed UNDO could restore the pre-move order; that was wrong.) `enable_log_exercise_button` is ship-dark, default OFF (`log_exercise_flags.dart`), so the move flow and its tests must cover the flag OFF (per-set check path) and ON.
- **`_persistSupersetGroups` (`train_provider.dart:1805`) writes `superset_group` into the stored schedule row by index, for every row, null included**, then saves through `upsertScheduled` (a synced write). After a session-only reorder, session index ≠ stored index, so a group id would land on the wrong stored exercise. Fix **[my call]**: match each session exercise to its stored row by identity (`exercise_id`, else `exercise_name`), consuming matches in list order so duplicate names pair first-to-first; write the group (null included) only onto matched rows; leave unmatched stored rows untouched. An exercise swapped in or added this session has no stored counterpart, and its grouping is simply not persisted (consistent with swap being session-only). With the order unchanged and nothing swapped, added or removed, the output is identical to today's index write. The same mismatch already exists today after remove/add; this fixes that too.
- **Superset origin and read path (verified):** the plan generator assigns `supersetGroup` to pairs on `legs` / `upper` / `full_body` / `shoulders_arms` days with ≥4 exercises (`superset_pairer.dart`); a Push day gets none unless the user pairs by long-press (`pairSuperset`, any two indices). When a workout opens, each stored row is read straight into `ExerciseData` (`superset_group` → `supersetGroup`, `train_provider.dart` ~L435). A card draws its coloured bar whenever its group is non-null, even if no partner exists.
- **Pre-existing, found by review:** `swapExercise` and the swap sheet's `ExerciseData(...)` never carry `supersetGroup` (`swap_sheets.dart` has no reference to it; `train_provider.dart` ~1605-1616), so swapping a superset member drops that slot from its group for the session while its partner keeps the tag, leaving the partner with a lone bar and no partner. The coach's plan swap, by contrast, keeps the slot's group (`swap_service.dart:530-531`). **[my call]** Unit 1 makes the in-workout swap carry the slot's `supersetGroup` (inside `swapExercise` only, the one writer — `swap_sheets.dart` is not edited; amended 2026-10-21 — plus a behavioural test), matching the coach path and the founder's "only that exercise changes, the rest is unaffected".
- **Day swap already owns these glyphs on the Train tab**: a `⇄ MOVED` tag and a `⇅` affordance on week rows (`week_rows.dart` ~L208, `day_swap_row_trailing.dart`), and copy "…or tap ⇅" (`day_swap_copy.dart` `allowanceHint`). Unit 1 lives on a different screen (active workout), so no clash on one screen; Unit 2 puts exercise controls on the same Train surfaces. See §10.
- Card State follows the exercise through the name-keyed `GlobalKey`; keep that. Duplicate names collide on that key today (pre-existing, OI-358); a move does not make it worse.
- **Board items that touch the same screen:** OI-357 (LOG batch 3) plans once-only hints through the same per-account `MigratedKey` + `UserConfigMigrator.userScopedKeys` mechanism this design uses for its hint flag; whichever lands first defines the helper and the other reuses it (check `origin/main` at build time; both edit the active-workout card and `userScopedKeys`). OI-356/357 and the LOG batches also edit `exercise_card.dart`, `screen.dart` and `train_provider.dart`: rebase and re-read before building. **OI-365** (filed 2026-10-21, audit of the several exercise-swap implementations) is deliberately NOT part of this batch; this design only carries `supersetGroup` through the in-workout swap (finding 1 of that OI).
- Hive-first, Riverpod only, no widget touching Hive directly, Wardroom palette, `AppTypography` (not raw GoogleFonts), dark theme only. Do not touch `plan_generator.dart` (§4.4 rule 14).
- A new reusable icon-button widget, if made shared, belongs in the wardroom barrel with a test.

## 7. Unit 1 — non-goals and anti-goals

Non-goals: saving the order to the plan; reorder anywhere outside the active workout; drag-and-drop; warm-up / cool-down reordering; a Profile entry for hints; any PRO gate (swap is free; move is free **[my call]**); cloud sync of the hint flag; changing the swap sheet's contents.
Anti-goals (a failure even if it "works"): a move that changes what gets logged or attributes logged sets to the wrong exercise; the hint blocking set entry; ⇅ and ⇄ being confused so often that users trigger the wrong one; any regression of today's swap, including the custom-exercise UNDO path.

## 8. Unit 1 — left to the builder

Widget structure; exact icon glyphs and sizes within the mockup's look; pure-function placement and name for the move logic; animation implementation (implicit vs explicit); exact snackbar and hint copy; telemetry events if any; flag key name.
Tests expected (§4.4 rule 21, mutated once each): a behavioural test of the pure move function (up, down, adjacent, a superset member moving alone with its group id travelling and its partner untouched, done-skipped, all maps remapped, undo round-trip); a test that an in-workout swap carries the slot's `supersetGroup`; a regression test for the superset-persist identity match (duplicate names, a swapped-in member, unchanged order equals today's output, scattered groups); both LOG-flag states; a per-account hint-flag test (stored in the user box, never configBox; cleared with the account's local data, so the next account — or the same one after a re-login — sees it again); widget tests for icons, semantics labels and the move flow.
Process: I expect M tier at least (§4.12.6: more than two product files, and a key registration in `core/services`); the builder tiers it. One worktree, plan reviewed twice before code, no APK unless asked.

## 9. Unit 2 — weekday exercise swap (separate build; summary only)

- **Today:** `SwapService.swapExerciseInDay(date, from, to)` (`swap_service.dart:411`) takes any date, refuses completed days, enforces equipment, keeps sets/reps/rest/superset, stamps `swapped_from`, and saves through `upsertScheduled` (per-date lock, Hive first, background sync). Its only callers are the AI coach, hard-wired to today. No Train-tab UI; the week rows and preview sheet are read-only.
- **Surfaces:** the future/past-day preview sheet (`exercise_preview_sheet.dart`) and today's inline expansion (`planned_expansion.dart`) share `_buildPreviewExerciseRow`, which also draws warm-up and cool-down rows (those get no swap icon).
- **Picker:** reuse `ExerciseSwapSheet` as-is (it hides ADD/REMOVE when its callbacks are null); add an optional scope line "Changes this *<weekday>* only".
- **Rules [my call]:** this date only; allowed only before START (an in-progress session owns its own list — `hasInProgressSession` exists); free and uncapped; UNDO snackbar 5 s.
- **Known work:** `swapped_via` is hard-coded `'ai_coach'` (`swap_service.dart:543`) and read nowhere — parameterise it. Invalidate the same providers the in-workout swap does (`todayWorkoutProvider`, `currentPlanProvider`, `calendarWeekProvider`). A swapped-away exercise feeds `TrainingHistoryAnalyzer.demotedExercises` (future plans avoid it) — a product effect to confirm. Plan regeneration writes rows with source `planGenerator` and would likely replace a swapped exercise: which regeneration paths reach a future date is **not traced**. Exercises persist to the cloud through the plan snapshot, not the per-day cloud table (which has no exercises column); the cloud round-trip is not traced end to end here.
- Not in scope for Unit 2 v1: "every future week" (new engine function, per-week sets/reps, atomicity across N rows).

## 10. Open for the founder

Unit 1: nothing open. The three questions raised by the builder check are answered: plain ship (decision 8), same glyphs (decision 9), swap carries the superset group and a move changes only the tapped exercise (my calls in §5/§6, which the founder can overrule).

Unit 2's own open items: the product effect in §9 (future plans avoid swapped-away exercises) and the cap/tier call.
