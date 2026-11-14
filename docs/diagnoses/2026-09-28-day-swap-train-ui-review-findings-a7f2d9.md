---
bug_id: a7f2d9
date: 2026-09-28
batch: day-swapper-sync-load (Task 25 fix round)
status: fixed
blast_radius: feature
symptom: |
  task-25-review.md (reviewing commit c9fbcd64, the unmerged day-swap Train
  UI feature) found 5 gaps, the two most consequential being real bugs
  rather than style nits:
  (1) lib/features/train/screens/train/week_rows.dart unconditionally
  inserted `DaySwapRowTrailing(date: ...)` + `const SizedBox(width: 8)` into
  every dated row's Row, and `const SizedBox(height: 8)` + a
  `DaySwapAllowanceLine` slot below the WardCard whenever any day was dated
  — regardless of `daySwapTrainUiEnabled()`. The two widgets correctly hid
  their OWN content when the `disable_day_swap_train_ui` kill switch was
  set, but the CALLER (week_rows.dart) still added the layout residue
  (an 8px gap before the EX count on every row; an 8px gap + an inert
  `Column` wrapper below the card, whose default `mainAxisSize.max` differs
  from `WardCard` alone) — so the kill switch never produced a genuinely
  byte-identical pre-feature layout, only visually-empty widgets sitting
  inside extra structure.
  (2) `test/widgets/day_swap_drag_wrapper_test.dart` had zero coverage of
  the kill-switch-OFF state, even though `DaySwapDragWrapper` has the
  widest OFF-state behavior change of the three day-swap widgets (an entire
  early-return branch, `if (!daySwapTrainUiEnabled()) return child;`).
  Three lesser findings bundled into the same fix commit: (3) `'DROP TO
  SWAP'`, `'moving…'` and the row's semantics label were inlined string
  literals instead of `DaySwapCopy` members, breaking the single-source-of-
  truth convention every other day-swap surface follows; (4)
  `_liftedDateProvider` was a `flutter_riverpod/legacy.dart` `StateProvider`
  — the repo's only use of that legacy API, all other new state having moved
  to `Notifier`; (5) the lifted-date reset (on drop/cancel) was proven only
  by a discarded one-off mutation-run probe, with no standing test.
concept: day_swap_train_ui_kill_switch
sot_registry_entry: null
writers:
  - { file: lib/features/train/screens/train/week_rows.dart, method_or_widget: "_buildCompactRow (day-swap trailing slot, pre-fix unconditional insertion)", line: 156 }
  - { file: lib/features/train/screens/train/week_rows.dart, method_or_widget: "_buildCompactWeekRows (allowance-line footer, pre-fix unconditional Column wrap)", line: 42 }
readers:
  - { file: lib/features/train/widgets/day_swap_row_trailing.dart, method_or_widget: "DaySwapRowTrailing.build (daySwapTrainUiEnabled read)", line: 46 }
  - { file: lib/features/train/widgets/day_swap_allowance_line.dart, method_or_widget: "DaySwapAllowanceLine.build (daySwapTrainUiEnabled read)", line: 22 }
  - { file: lib/features/train/widgets/day_swap_drag_wrapper.dart, method_or_widget: "DaySwapDragWrapper.build (daySwapTrainUiEnabled read)", line: 75 }
hive_key_prefix: "disable_day_swap_train_ui (existing kill-switch key, configBox — not introduced by this fix)"
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "test/widgets/week_rows_kill_switch_test.dart (new — asserts by widget type/key and child count, not pixels), plus updated test/widgets/day_swap_drag_wrapper_test.dart (new switch-OFF test, F3) and its new F5 standing-reset group"
ist_handling:
  - "No date-key logic touched — the fix is purely conditional widget-tree construction and copy sourcing; DaySwapRules.mondayOf/istDateStr call sites are unchanged."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure client-side widget-tree/copy fix reading only the existing local configBox kill-switch flag; no Hive write, no cloud read or write."
forbidden_patterns_checked:
  - { pattern: "A kill-switch fix that hides only the WIDGET's own content and leaves the CALLER's layout residue (the exact bug this diagnose-doc fixes)", absent: true }
  - { pattern: "A new standing test asserting on a UI signal (the 'moving…' placeholder) that is actually governed by Flutter's own internal drag-session lifecycle rather than by the app's own state — confirmed misleading by mutation-testing before being replaced with the lock-glyph observable", absent: true }
proposed_fix: |
  F1: added DaySwapCopy.dropToSwap, .movingLabel, .swapSemanticsLabel(date);
  day_swap_drag_wrapper.dart and day_swap_row_trailing.dart now route
  through them instead of inline literals.
  F2: extracted week_rows.dart's two unconditional insertion sites into
  top-level, directly-testable functions — daySwapRowTrailingSlot(date)
  (returns [] when date is null or the switch is off) and
  wrapWithDaySwapAllowanceFooter(card, anyDatedIstDate) (returns card
  itself, same instance, when the switch is off or the week has no dated
  day) — so week_rows.dart's own additions vanish entirely with the switch
  off, matching the pre-feature 9f33dbef:week_rows.dart tree exactly. A
  `part of` file's public top-level declarations are visible to any file
  importing the parent library (screen.dart), so the new test pumps these
  functions directly without booting the heavy TrainScreen.
  F3: added a kill-switch-OFF test to day_swap_drag_wrapper_test.dart:
  long-press does not lift, no target chrome, no confirm sheet.
  F4: converted _liftedDateProvider from a flutter_riverpod/legacy.dart
  StateProvider to a plain NotifierProvider<_LiftedDateNotifier, String?>
  with lift()/clear() methods; removed the legacy import. Kept
  non-autoDispose to preserve the StateProvider's exact prior lifetime
  (never disposed either) — a pure API migration, no behavior change.
  F5: added a standing F5 test group covering all three drag-termination
  paths. Mutation-testing (see below) found the widget's three reset call
  sites are triple-redundant (Flutter's onDragEnd fires unconditionally
  regardless of acceptance), and separately found the "moving…" placeholder
  is NOT a reliable observable of the app's own `_liftedDateProvider` state
  post-gesture (Flutter's Draggable reverts its own internal dragging state
  on release regardless of app state) — the tests were corrected to assert
  the lock-glyph residual chrome on the other (locked) row instead, which
  IS driven by `_liftedDateProvider`.
regression_test_planned:
  - test/widgets/week_rows_kill_switch_test.dart
  - test/widgets/day_swap_drag_wrapper_test.dart
  - test/widgets/day_swap_row_trailing_test.dart
impact_analysis: |
  Purely additive/corrective inside three already-new, unmerged widget
  files plus one already-new copy file and one already-new screen part
  file — none of which has shipped to `main` yet (this whole feature is
  mid-batch, worktree day-swapper-sync-load). No existing production
  surface is touched. The Notifier migration (F4) is API-shape-identical to
  the StateProvider it replaces (same read/write semantics via
  lift()/clear() instead of `.state =`), verified by the full existing
  DaySwapDragWrapper suite staying green untouched. flutter analyze lib/ —
  51 pre-existing infos elsewhere (verified against the pre-fix baseline),
  zero new warnings/errors. test/contracts/ — 4110 passed, 1 skipped, 0
  failed (full run, unaffected by this diff).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ — same 51 pre-existing infos as baseline, zero new warnings/errors; day_swap_copy.dart, day_swap_row_trailing.dart, day_swap_drag_wrapper.dart, week_rows.dart all compile clean." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The only Hive read involved is the existing disable_day_swap_train_ui configBox flag, unchanged by this fix; DaySwapRowTrailing/DaySwapAllowanceLine/DaySwapDragWrapper kill-switch tests (task-25's own suite) stay green." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched — pure Flutter widget-tree/copy fix." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire change — no Edge Function, no Supabase call in any of the five touched files." }
mutation_proven:
  mutated: "F2: daySwapRowTrailingSlot's `date == null || !daySwapTrainUiEnabled()` guard narrowed to `date == null` (grep -c of the removed clause: 0). F3: DaySwapDragWrapper's `if (!daySwapTrainUiEnabled()) return child;` replaced with `if (false) return child;` (grep -c of the original line: 0). F5: three separate single-call removals (onAcceptWithDetails's explicit clear, onDraggableCanceled, onDragEnd) each confirmed applied by grep -c, then a combined removal of all three at once."
  result: "F2: exactly 1 test reddened (the OFF-layout pre-feature-tree assertion); the other 6 in that file stayed green. F3: exactly 1 test reddened (the new switch-OFF test); the other 8 in that file (5 original + 3 F5) stayed green. F5: each of the three SINGLE-call removals reddened ZERO tests — investigated and confirmed genuinely redundant (Flutter's onDragEnd fires unconditionally on every drag termination, accepted or not, so any one of the three calls alone is masked by the others); the COMBINED removal of all three reddened all 3 F5 tests, proving the standing tests do detect a stuck lifted date. That investigation also surfaced that the tests' original 'moving…' assertions were not observing app state at all post-gesture (Flutter's own Draggable clears its internal dragging visual on release independent of _liftedDateProvider) — the tests were corrected to assert the lock-glyph chrome on the other row instead, which is driven by the provider."
  confirmed_applied: "Every mutation confirmed via grep -c before running tests; every mutation confirmed to compile via flutter analyze on the touched file; every mutation restored afterward and verified via diff against a pre-mutation backup copy (git diff / plain diff both clean)."
---

## Summary

Task 25 (Train week-list day-swap drag/⇅/MOVED-tag/allowance-line, commit
c9fbcd64) shipped correct WIDGET-level behavior for its kill switch
(`disable_day_swap_train_ui`) but the CALLER — `week_rows.dart` — kept
inserting its own layout (spacers, a wrapping `Column`) around those
widgets regardless of the switch, so "kill switch on" never actually
matched the pre-feature layout. Three smaller gaps (hardcoded copy
bypassing `DaySwapCopy`, a missing kill-switch-OFF test for the widest
OFF-state widget, a legacy `StateProvider` with no standing reset test)
shipped in the same review round and are fixed in the same commit.

## Root cause

`DaySwapRowTrailing`/`DaySwapAllowanceLine` each correctly render nothing
(or reduced content) when `daySwapTrainUiEnabled()` is false, but
`week_rows.dart` — written before those widgets existed as a coherent
"day-swap block" — still hard-coded the surrounding `SizedBox`/`Column`
structure unconditionally, at the CALL SITE. Hiding a widget's own content
is not the same as the CALLER not adding structure around it; nothing
enforced that equivalence, and no test pumped the caller (the original
Task 25 brief explicitly avoided pumping the full `TrainScreen` — heavy
screen, `GoogleFonts`/`path_provider` risk, no existing harness — so the
caller-side residue was invisible to the suite).

## Fix

Extracted the two caller-side insertion decisions into top-level,
independently-testable functions (`daySwapRowTrailingSlot`,
`wrapWithDaySwapAllowanceFooter`) declared in `week_rows.dart` itself (a
`part of screen.dart` file, so the functions are visible to any file
importing `screen.dart` without needing to construct `TrainScreen`).
`week_rows.dart` now calls these instead of inlining the conditional
logic, and a new test file pumps them directly to assert the OFF-switch
tree is exactly the pre-feature tree (by widget type and child count).

## Verification

- Combined run (3 Task 25 widget test files + 2 Task 24 sheet test files +
  the new `week_rows_kill_switch_test.dart`, one `flutter test` invocation,
  `--timeout 90s`): 40/40 passed (re-run twice for stability; a lone
  transient failure on an unrelated third run was confirmed a flake — the
  same 40/40 green afterward with a clean `git diff` against the intended
  fix).
- `flutter test test/contracts/`: 4110 passed, 1 skipped, 0 failed —
  unaffected by this diff.
- `flutter analyze lib/`: 51 pre-existing infos (same as the pre-fix
  baseline), zero new warnings or errors.
- Mutation-proof: see `mutation_proven` above. The F5 investigation is the
  most substantive finding of this fix round: the widget's three
  drag-termination reset calls turned out to be intentionally-redundant
  defensive code (traced to Flutter's own `Draggable` contract, where
  `onDragEnd` fires unconditionally on every termination regardless of
  acceptance), and the original test design's core observable (`'moving…'`
  text) was not actually sensitive to the app's own provider state after
  the gesture ends — both facts were surfaced only by running the mutations
  and reading the actual (surprising) results rather than assuming the
  planned mutation-to-test mapping would hold.

## Related bugs

None — this is a review-fix round on an unmerged, mid-batch feature
(`day-swapper-sync-load`), not a production regression.

## Fix round 2 correction (task-25-fix2, 2026-09-28)

Fix round 1's F2 fix (above) was applied one notch too literally: it made
`daySwapRowTrailingSlot` return `const []` whenever `date == null ||
!daySwapTrainUiEnabled()`, which — with the switch off — omitted
`DaySwapRowTrailing` from the row entirely, including its "⇄ MOVED" tag.
That contradicts the spec (`docs/superpowers/specs/2026-09-26-day-swapper-design.md`
lines ~217, ~699, ~736: "The '⇄ MOVED' tag stays until the day is
completed" / "After a swap, both rows show '⇄ MOVED' until completed. DONE
always wins over MOVED.") and `task-25-brief.md` design decision 3 ("The
MOVED tag stays visible either way … hiding it would make an already-
swapped day look unswapped"). Fix 1's own report flagged this exact tension
under "Concerns" without resolving it.

**Coordinator ruling:** the kill switch stops NEW swaps (the ⇅ affordance
and the drag interaction) — it must not hide swaps that already happened
(the MOVED-tag display of past state).

**Fix:** `daySwapRowTrailingSlot(String? date)` now checks, only when the
switch is off, whether the day is already moved
(`SwapService.instance.weekStates(date)` → `DaySwapDayState.isMoved`, the
same canonical predicate `DaySwapRowTrailing` itself watches via
`daySwapWeekProvider`) and keeps the slot (so the MOVED tag still renders)
when it is. A non-moved day, or a moved-but-completed day (DONE wins over
MOVED — already baked into `DaySwapRules.isMoved`'s `status != 'completed'`
clause), still gets `const []`, preserving the pre-feature byte-identical
layout fix 1 established. `DaySwapRowTrailing` itself is unchanged — it
already correctly hides only the ⇅ affordance (`enabled && state.movable`)
while always rendering the MOVED tag when `state.isMoved`; the bug was
entirely in the caller's slot-insertion decision, not in the widget.

Two new tests added to `test/widgets/week_rows_kill_switch_test.dart`:
"OFF plus a swapped, uncompleted day — MOVED shows, no ⇅ affordance" and
"OFF plus a swapped AND completed day — no MOVED tag (DONE wins, spec)".
The original OFF/no-swaps byte-identity test is unchanged and still green.

Mutation-proof: (1) reverting the guard to fix 1's original
`date == null || !daySwapTrainUiEnabled()` reddened exactly 1 test (the new
MOVED-visible-when-OFF test); the other 8 stayed green. (2) Removing the
guard entirely (always inserting the slot) reddened exactly 2 tests (the
OFF/no-swaps byte-identity test and the OFF+completed test) — the two cases
that must produce an empty slot; the other 7 stayed green. Both mutations
confirmed applied via `grep -c`, confirmed to compile, and restored with a
clean `diff` against a pre-mutation backup afterward.

Also repointed `test/contracts/day_of_week_canon_writer_to_reader_test.dart`'s
stale `week_rows.dart:54` prose citation (CLAUDE.md §4.9 conversion-on-touch)
to a symbol reference (`_buildCompactRow`'s `dayLabel = 'D${day.dayNumber}'`
fallback) instead of a line number, since that file only ever reads
`date_utils.dart`-family sources and never source-greps `week_rows.dart`
itself — assertions unchanged.

## B-pass remediation (2026-09-28, review `docs/reviews/day-swapper-sync-load-bpass.md`)

- **R2-F1 (P1) — Train drag showed a spent free user a normal confirm sheet.** Writer of the gate:
  `SwapPickerSheet.build` (`!isPro && allowance.spent` → the upsell); reader that lacked it:
  `SwapConfirmSheet.build`, reached from `DaySwapDragWrapper`'s drop. SWAP could only answer "This
  week's swap is spent." with no way to PRO. Fix: the spent sheet is public (`DaySwapSpentSheet`,
  one `forContext` factory opening the one paywall) and both sheets return it under the same
  condition. Tests (`test/widgets/swap_confirm_sheet_test.dart`): spent free user → upsell, and the
  mirror — a free user with a swap left still gets SWAP. Mutation — disable the confirm-sheet gate →
  1 red (the spent test), mirror green.
- **R2-F3 (P2) — a REFUSED coach swap left the Train week stale.** `ToolDispatcher.execute` returned
  on `!result.success` before its `swap_workout_days` invalidation block, and a refusal bumps no
  allowance revision, so the block was the only refresh path — and a refusal is exactly the case
  where the cached week is out of date. Moved above the early return (`DaySwapController._refresh`
  already refreshes on every outcome). Test: "a REFUSED coach swap still refreshes
  daySwapWeekProvider" (`tool_dispatcher_day_swap_invalidation_test.dart`). Mutation — gate the
  block on `result.success` → 1 red (expected completed lock, got null).

## Hermes remediation (2026-09-28)

- **L16 — `daySwapAllowanceProvider` did not rebuild on an account switch.** Reader
  `day_swap_provider.dart` watched only `subscriptionInfoProvider.isPro`; the count it reads lives
  in the per-user userBox (writer `DaySwapAllowance.recordSwap` / `_consume`). Between two accounts of
  the same tier, B was shown A's spent week — and the drag confirm sheet's spent-upsell reads this
  provider. Fix: `ref.watch(authUserIdTokenProvider)` (the c4055a convention). Test:
  `test/features/train/day_swap_provider_test.dart` "rebuilds on an account switch" — red before
  (`Expected: <0> Actual: <1>`), green after.
- **L34 — the coach swap's invalidate failure only reached `debugPrint`.** `tool_dispatcher.dart`
  now also records it (`tool_dispatcher_day_swap_invalidate`).
- **L15 — `SwapService._weekLocks` survives an account switch by design** (dropping a held lock
  would let two swaps overlap); `_onUserChanged`'s "No in-memory caches" comment corrected.
