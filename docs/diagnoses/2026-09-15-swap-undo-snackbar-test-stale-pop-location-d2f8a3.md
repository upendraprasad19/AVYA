---
bug_id: d2f8a3
date: 2026-09-15
batch: obs-batch-0914 CI red follow-up
status: fixed
blast_radius: feature
symptom: |
  `main` CI ("Test & Analyze" → "Unit Tests") went RED at e46cecc9 (the
  obs-batch-0914 merge) with:
    test/contracts/swap_undo_snackbar_modal_pop_test.dart: s1n4c0 — onAdd
    "__ADD_MODE__" handler pops outer swap sheet before opening create sheet
    Expected: a non-negative value
    Actual: <-1>

  Root cause: diagnose 6c2f91 (this same batch) correctly removed a
  double-pop regression — a redundant `Navigator.of(ctx).pop()` inside
  `_showSwapSheet`'s onAdd handler (swap_sheets.dart) that assumed the swap
  sheet was still on the Navigator stack when it ran. It was not:
  `ExerciseSwapSheet`'s own "+ ADD EXERCISE" button
  (exercise_swap_sheet.dart) already self-pops before invoking `onAdd`,
  making the swap_sheets.dart pop a genuine double-pop that ejected the
  active workout screen instead.

  `test/contracts/swap_undo_snackbar_modal_pop_test.dart` — a PRE-EXISTING
  source-grep test from bug s1n4c0 (APK Test #16.2), never touched by this
  batch and never grepped for before removing the pop — asserted the pop
  at its OLD location (swap_sheets.dart's onAdd handler). Removing that
  pop is exactly what 6c2f91 fixed to do, so the stale test broke as an
  automatic, structural consequence of the fix. `swap_add_exercise_double_
  pop_behavioral_test.dart` (6c2f91's own new regression test) grepped
  ONLY for the double-pop shape it was written to catch and could not see
  this unrelated, older assertion in a different file.
concept: active_workout_swap_add_exercise_navigation
sot_registry_entry: |
  Not applicable — same as 6c2f91, a navigation-stack correctness contract,
  not a new writer/reader concept. No Hive/cloud field, key, or contract
  change; this fix touches only a test file.
writers:
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: "\"+ ADD EXERCISE\" WardButton onPressed — self-pop before invoking onAdd (unchanged by this fix — already correct)", line: 213 }
readers:
  - { file: test/contracts/swap_undo_snackbar_modal_pop_test.dart, method_or_widget: "source-grep asserting the swap-sheet pop's location — REPOINTED by this fix from swap_sheets.dart (stale, post-6c2f91) to exercise_swap_sheet.dart (current)", line: 25 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/swap_undo_snackbar_modal_pop_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure source-grep test, no Hive/cloud access."
forbidden_patterns_checked:
  - { pattern: "swap_undo_snackbar_modal_pop_test.dart reading lib/features/train/screens/active_workout/swap_sheets.dart for the ADD-flow pop (the stale, pre-6c2f91 location)", absent: true }
proposed_fix: |
  Repoint the test (never loosen or delete it — the underlying contract is
  still true, it just moved). Read `exercise_swap_sheet.dart` instead of
  `swap_sheets.dart`; locate the `__ADD_MODE__` sentinel; walk BACKWARD to
  the nearest enclosing `onPressed: () {` (so the assertion cannot
  accidentally match the sheet's close-icon pop or the DELETE button's own
  pop, both of which also call `Navigator.of(context).pop()` elsewhere in
  the same file); assert the self-pop is found between that `onPressed`
  and the sentinel, i.e. BEFORE `onAdd` is invoked.
regression_test_planned:
  - test/contracts/swap_undo_snackbar_modal_pop_test.dart
impact_analysis: |
  Zero production code change. This fix is a test-only correction that
  makes the test assert the TRUE current location of the self-pop instead
  of a location diagnose 6c2f91 correctly emptied out. The underlying
  UNDO-snackbar-shadowed-context contract (bug s1n4c0's original concern)
  was never actually broken by 6c2f91 — 6c2f91's own diagnose-doc states
  exercise_swap_sheet.dart's self-pop "already solves that" — only this
  test's assertion of WHERE to find it was stale.

  Not affected: the swap sheet's direct exercise-select path, the Delete
  button, and the active workout screen's own top-level "+ ADD EXERCISE"
  button — none of those are read by this test and none changed here.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Test-only change; flutter analyze test/ clean; the production file it now reads (exercise_swap_sheet.dart) is unchanged and was already correct." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Pure source-grep test, no Hive access." }
---

## Summary

`main` went red at the `obs-batch-0914` merge commit (`e46cecc9`) because a
PRE-EXISTING test from bug `s1n4c0` (APK Test #16.2) asserted the ADD-flow
Navigator pop at its OLD location (`swap_sheets.dart`'s onAdd handler) — the
exact line diagnose `6c2f91`, shipped in the same batch, correctly removed
as a double-pop regression. The underlying contract the old test protected
(the swap sheet must be popped before the create-sheet's UNDO snackbar
fires, so the snackbar's auto-dismiss timer isn't hosted against a shadowed
context) was never broken; `exercise_swap_sheet.dart`'s own self-pop on the
"+ ADD EXERCISE" button already satisfies it and always has. Only the old
test's assertion of WHERE that pop lives was stale.

## Bug-history lookup (CLAUDE.md §4.1.5)

This is the exact class CLAUDE.md's own pitfall table already documents:
"Extracting or moving code breaks source-grep contracts in files you never
touched — grep the test tree for what is moving." That grep was not run
before removing the pop in `6c2f91`'s implementation turn; `grep -rl
"s1n4c0\|__ADD_MODE__" test/` (run as part of THIS fix) found exactly the
one stale file, confirmed no others exist.

## Root cause

Two facts, both already established by `6c2f91`'s own diagnose-doc,
combined to break a THIRD file neither of them touched:

1. `exercise_swap_sheet.dart:213-219`'s "+ ADD EXERCISE" button already
   self-pops (`Navigator.of(context).pop()`) BEFORE invoking
   `widget.onAdd!(SwapExerciseData(name: '__ADD_MODE__', ...))`.
2. `6c2f91` removed `swap_sheets.dart`'s redundant second pop in the onAdd
   handler for that same sentinel.

`test/contracts/swap_undo_snackbar_modal_pop_test.dart`, written for bug
`s1n4c0` before `exercise_swap_sheet.dart`'s self-pop existed, asserted the
pop specifically inside `swap_sheets.dart` — the location `6c2f91` emptied
out. The assertion was never re-pointed when the self-pop was added
independently at some earlier point, so it kept passing by coincidence
(TWO pops existed, and the test only checked for one of them) until
`6c2f91` removed the one it was actually looking at.

## Fix

Repointed `swap_undo_snackbar_modal_pop_test.dart` to read
`exercise_swap_sheet.dart` and assert the self-pop there, anchored to the
nearest enclosing `onPressed` before the `__ADD_MODE__` sentinel (so it
cannot false-match the sheet's close icon or the DELETE button's own
pops elsewhere in the same file). Never loosened or deleted — the
contract is still true, it just moved, matching this repo's own documented
recovery pattern for this exact class.

## Verification

`flutter test test/contracts/swap_undo_snackbar_modal_pop_test.dart` — 1/1
green after the repoint.

**Mutated and run** (rule 21): removed the self-pop from
`exercise_swap_sheet.dart`'s "+ ADD EXERCISE" `onPressed` (the exact
shape this test now guards against), ran
`test/contracts/swap_undo_snackbar_modal_pop_test.dart` +
`test/contracts/swap_add_exercise_double_pop_behavioral_test.dart`
together (5 tests): the repointed test reddened exactly as expected
(`Expected: a non-negative value, Actual: <-1>`); one test in the OTHER
file's own mutation-fixture also reddened as a side effect of mutating
shared production code that both files exercise (its "FIXED caller" case
stayed green — only its own separate "MUTATION: extra pop" fixture, which
assumes the self-pop is intact and adds a second pop on top to simulate
the pre-6c2f91 double-pop shape, broke because the extra pop was now the
ONLY pop). Restored the self-pop; all 5 tests green again.

`flutter analyze test/` clean.

## Related

Direct fallout of `6c2f91` (Obs 5) in the same batch — see that
diagnose-doc for the original double-pop investigation. Same recurring
class as the `docs/playbook/common-pitfalls.md` entry "Extracting or
moving code breaks source-grep contracts in files you never touched"
(profile-phase-fixes batch, 2026-08-30) — this is its most direct
recurrence: a REMOVAL rather than a move/extraction, but the same failure
to grep the whole test tree before landing.
