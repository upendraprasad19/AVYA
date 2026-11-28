---
reviewed_at: 2026-11-03T09:40:00+05:30
staged_against: 57a629d5c6ea
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: pending
verdict_note: all 10 findings triaged by the author (8 accepted and fixed, 2 false_alarm with evidence); the founder's acceptance of the triage is requested in the close-out message. At account tier the verdict is advisory.
---

# Code Review - library-batch-m2b (Part A: LOG-mode rows to the card edge + tile-led header)

Reviewed state: worktree `.claude/worktrees/m2b-mockup`, HEAD `b23e8661`, the staged diff (24 files) whose first
staging hash was `67e0310d8e85`. The reviewer (a fresh Sonnet subagent, 92 tool uses) found no P0 and no break in the
built behaviour; the risk it reported was TEST STRENGTH: seven mutations that re-introduce a real regression stayed green
across all 165 tests of `test/features/train/log_exercise/` and the media contract test. The fixes below changed the
staged diff, so the file is named for the hash of the staged diff as it is committed (`57a629d5c6ea`).

## Finding 1 - P1 - guard_without_its_mirror
- **file:line:** `lib/features/train/screens/active_workout/exercise_card.dart:1477-1478` (`allDone`)
- **claim:** the "every exercise is done, so freeze" guard had only its all-done side tested (both cases used a one-exercise session). `.every` changed to `.any` stayed green; in the app that freezes the tile of every next card after the first exercise is logged (the main path: LOG, then auto-advance).
- **verification:** change `.every((done) => done)` to `.any(...)` and run `test/features/train/log_exercise/`.
- **suggested-fix:** a two-exercise case where the other exercise is done and the focused one is not.
- **status:** accepted, fixed. Test `ANOTHER exercise done, this one not: the tile still autoplays` in `exercise_header_tile_test.dart`. Mutation m1 (`.any`) reddens it (1 test).

## Finding 2 - P2 - guard_without_its_mirror
- **file:line:** `lib/features/train/widgets/set_input_row.dart:120` (`final tick = !interactiveCheck && isChecked;`)
- **claim:** the per-set path's only test seeded no checked set; `tick = isChecked` stayed green and would show a second tick and lose the warm-up W.
- **verification:** `git grep -l SetInputRow -- test`; apply the mutation.
- **suggested-fix:** seed a checked set and a checked warm-up in the per-set case.
- **status:** accepted, fixed. Test `a checked set and a checked warm-up keep their number tile` in `log_exercise_rows_edge_test.dart`. Mutation m2 reddens it (1 test).

## Finding 3 - P2 - guard_without_its_mirror ("follow the return value to its call site")
- **file:line:** `lib/features/train/screens/active_workout/exercise_header_tile.dart` (Semantics wiring)
- **claim:** the tile's semantics were checked only by `hasAction(tap)` and `hasAction(longPress)`; swapping the two handlers stayed green, so a screen-reader user's activate would start superset grouping.
- **verification:** swap `onTap` and `onLongPress` on the Semantics.
- **suggested-fix:** perform the actions through the semantics tree and assert the handler each reaches.
- **status:** accepted, fixed. Test `activate opens the sheet; long press starts grouping, never the other way round` (uses `tester.semantics.tap` / `longPress`). Mutation m3 reddens it (1 test).

## Finding 4 - P3 - guard_without_its_mirror
- **file:line:** `lib/features/train/widgets/set_input_row.dart:316-317`
- **claim:** `IgnorePointer` and `ExcludeSemantics` on the arrow overlay were pinned by nothing (each removal stayed green).
- **suggested-fix:** tap at the arrow's centre and expect the KG box focused; assert the field's label does not contain the glyph.
- **status:** accepted, fixed. Test `the arrow overlay is inert`. Mutations m4a (no `IgnorePointer`) and m4b (no `ExcludeSemantics`) each redden it (1 test each).

## Finding 5 - P3 - asserted_fixture_value
- **file:line:** `lib/features/train/screens/active_workout/exercise_header_tile.dart:71`
- **claim:** the 124 dp assertions measured the frame; `size: kHeaderTileSize` changed to `size: 62` stayed green and "the picture would be a 62 dp animation in an empty 124 dp frame".
- **status:** accepted in part, fixed. The reviewer's description of the effect was wrong (the frame's tight constraints force the view to 124 dp whatever it is told, so a `getSize` assertion on the view CANNOT show the mutation; the first version of the new test also stayed green under it, found by running the mutation). What the wrong value changes is the DECODE width (soft picture, stretched). The test now also asserts `ExerciseAnimationView.size == kHeaderTileSize`. Mutation m5 reddens it (1 test).

## Finding 6 - P3 - missing positive/negative pair
- **file:line:** `lib/features/train/screens/active_workout/exercise_header_tile.dart:85`
- **claim:** the grouping-mode case asserted "no sheet" and "no Enlarge semantics" but not that the ENLARGE chip is absent; the chip is under `ExcludeSemantics`, so a dead chip would pass.
- **status:** accepted, fixed. `ENLARGE` is asserted present on the normal tile and absent in grouping mode. Mutation m6 (chip also when only `onLongPress` is set) reddens the grouping case (1 test).

## Finding 7 - P3 - guard_without_its_mirror (state loss)
- **file:line:** `lib/features/train/screens/active_workout/exercise_header_tile.dart:95-120`
- **claim:** `build` returned a different ROOT widget type per `(onEnlarge, onLongPress)` state (`SizedBox`, `GestureDetector`, `Semantics`); entering or leaving superset grouping on the focused card changes the type, throws away the `ExerciseAnimationView` State and restarts the animation from the still. Cosmetic, read from `Widget.canUpdate`, not executed by the reviewer.
- **verification:** the new test fails on the unfixed code at the first flip (`enlarge false, long press true: the view State must survive`).
- **status:** accepted, fixed. One wrapper chain (`Semantics` over `GestureDetector`) in every state; the Semantics adds no node when there is no enlarge handler, so the grouping-mode semantics are unchanged. Test `onEnlarge / onLongPress turning null and back never remounts the animation view` (RED before the fix, GREEN after). Mutation m7 (the old per-state shape) reddens it (1 test).

## Finding 8 - P3 - writer_reader_drift (comment and plan claim vs arena rule)
- **file:line:** `exercise_card.dart:1137-1143` (the comment as reworded; it was `:1137-1141` before) and plan call C-f
- **claim:** the comment said the thumb's tap in grouping mode "belongs to the group-select, like the header's"; the header Row is itself an opaque detector whose tap is `onFocus`, so a thumb or name tap focuses, while the new tile (no detector around it) lets its tap fall through to the card's group-select (`pairSuperset(self)`, which cancels grouping on the source card). Not a regression (the old thumb opened the sheet), but the comment was wrong and the group-select path was unobserved.
- **verification:** `exercise_card.dart:1066` (the card's outer detector, group-select) and `:1119` (the header's own tap, `_headerTap`); read `train_provider.dart:1915` (`pairSuperset`).
- **status:** accepted, fixed. Comment reworded to say exactly that; the grouping-mode case now asserts the tile's tap reaches the card's group-select handler once. Mutation m8 (a no-op tap handler that swallows it) reddens it (1 test).

## Finding 9 - P3 - guard_without_its_mirror (blast of a throw)
- **file:line:** `exercise_card.dart:167` and `:368`
- **claim:** `resolveMedia` now runs in the card's own `initState`, so a community row whose name is not a String (`getByExactName`'s hard `as String?` cast) fails the WHOLE card, where a throw in the thumb "replaced only the thumb slot".
- **status:** false_alarm. A guard (`_resolveMediaOrNull`) and a test were written first; the test FAILED with the guard in place (0 text fields). Probe: the same corrupt row with the card in its THUMB layout (main's code path, `isFocused: false`) also leaves 0 text fields: a child's `initState` failure is caught by the nearest `ComponentElement`'s `updateChild`, which replaces that whole subtree, so on main the thumb's own `resolvePlate` / `resolveMedia` already takes the card down. The new code is not worse than the old for this input, and a guard in the card alone cannot help. Guard and test removed; the latent hard cast in `exercise_repository.dart:53,74` is pre-existing, needs a `name` that is not text in a Postgres `text` column, and is out of this batch's files.

## Finding 10 - P3 - blast_radius_mismatch (design note)
- **file:line:** `test/contracts/exercise_media_reads_without_storage_from_test.dart:38-41`
- **claim:** `exercise_card.dart` and `screen.dart` in `_expected` make the `[w]` pin ("no animation file gates on the subscription") scan two large files, so a later unrelated PRO gate there fails it; `_mentionOnly` would exempt them.
- **status:** false_alarm. The card owns the tile's show condition (`_showHeaderTile`), which is exactly where a subscription gate would break C7 (free to every tier); `_mentionOnly` would remove that protection. A future unrelated gate in those files fails loudly with the file and the pattern named, and its author reads the reason. Kept as a deliberate trade.

## Checked and clean
Per the reviewer (92 tool uses, baseline 165 tests green before any mutation, `dart analyze` clean on every staged `.dart` file): lens 1 (no Hive or cloud write in the diff; `media_slug` / `media_version` read only through `resolveMedia`; the three `sot_registry.yaml` ranges opened by hand, each shifted +26 correctly; the LAST/TRY move has no per-site extras to lose and the TRY gate is covered in both layouts), lens 2 (0 `functions.invoke`), lens 3 (`lib/core/**` account, the rest feature), lens 4 (0 secret-shaped hits, no invisible characters), lens 5 (one new `unawaited(ExercisePlateSheet.show(...))`, no error path to lose), lens 6 (the show-condition mirrors, `noTap` in grouping mode, the freeze against every route kind: no `useRootNavigator` under `lib/`, the finish dialogs go to the root navigator and leave the tile looping as the plan accepts), lens 7 (stills and `kTinyPng` exist, `objectName` literal matches), lens 8 (every asserted literal recomputed).

## Mutation log (reviewer, all files restored, sha256 equal)
`.every`->`.any` survived; swap Semantics handlers survived; drop `IgnorePointer` survived; `tick = isChecked` survived; `size: 62` survived; chip also on `onLongPress` survived; drop `ExcludeSemantics` survived. After the fixes each of them is killed (author's mutation run, all files compared identical after restore): m1=1, m2=1, m3=1, m4a=1, m4b=1, m5=1, m6=1, m7=1, m8=1.

## Author's gate loop after the fixes
`flutter analyze --no-fatal-infos` on the whole project: 0 errors, 0 warnings, 396 infos (the baseline; none in this batch's files). `test/features/train/log_exercise/` plus the media contract test: 171 passed. Full suite before the fixes: 9752 passed, 25 skipped, 2 failed (both fail identically on a clean checkout of `b23e8661`; see the closure ledger row `M2B-A-SUITE-WINDOWS`).

## Founder triage notes
<filled in by the founder>

## Tuning entry
- **2026-11-03** - blast-radius account - 10 findings; 2 false_alarm (20%); tuning: none to the lens set. Lens 6's "mutate it and run it" method earned its cost again (7 surviving mutants of the diff's own new tests, 3 of them the same shape as the batch's own prior escapes). Two cautions to carry: a reviewer's claim about WHAT a mutation does at runtime must be checked by running it (finding 5: the layout claim was wrong, and my first fix for it also survived the mutation), and a reviewer's claim about Flutter's error scope (finding 9: "replaces only the thumb slot") must be probed before code is written (it was wrong: an `initState` throw in a child takes the whole card).
