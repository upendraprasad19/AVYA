---
bug_id: 6c2f91
date: 2026-09-15
batch: Internal-testing observation batch, session 2 (Obs 5)
status: fixed
blast_radius: feature
symptom: |
  Founder-reported, live-reproduced jointly with the agent in Chrome on the
  amar@gmail.com test account: mid active-workout, after logging all 4 sets
  of an exercise, tapping SWAP on the next exercise then "+ ADD EXERCISE"
  inside the swap sheet, then dismissing the create-custom-exercise sheet
  (pull-down) without creating anything — the app landed back on the Train
  tab's "start workout" screen with ALL logged progress (completed sets,
  elapsed timer) apparently lost. Founder: "i am swapping and clicking add
  exercise and then when i dont want to add exercise, i an back to start
  workout screen with all progress lost."
concept: active_workout_swap_add_exercise_navigation
sot_registry_entry: |
  Not applicable — this is a navigation-stack correctness fix (an extra
  Navigator.pop() call), not a new writer/reader concept. No Hive/cloud
  field, key, or contract changes.
writers:
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: "\"+ ADD EXERCISE\" WardButton onPressed — self-pop before invoking onAdd", line: 214 }
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, method_or_widget: "_showSwapSheet onAdd handler for the '__ADD_MODE__' sentinel", line: 97 }
readers:
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, method_or_widget: "_openCreateAndAutoSwap — opens CreateCustomExerciseSheet on the context passed to it", line: 144 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutNotifier.startWorkout — unconditional, no-confirmation full reset", line: 907 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/swap_add_exercise_double_pop_behavioral_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure in-session Navigator + provider state, no Hive/cloud read across accounts."
forbidden_patterns_checked:
  - { pattern: "swap_sheets.dart's onAdd handler for '__ADD_MODE__' calling Navigator.of(ctx).pop() before _openCreateAndAutoSwap", absent: true }
proposed_fix: |
  Delete the redundant Navigator.of(ctx).pop() in swap_sheets.dart's onAdd
  handler for the '__ADD_MODE__' sentinel. exercise_swap_sheet.dart's own
  "+ ADD EXERCISE" button (line 214) already pops the swap sheet on itself
  before invoking onAdd, so by the time onAdd runs the swap sheet is already
  gone. The extra pop in onAdd was popping the NEXT route down instead — the
  active workout screen's own page — ejecting the user to the Train tab.
  _openCreateAndAutoSwap is the only action needed there.
regression_test_planned:
  - test/contracts/swap_add_exercise_double_pop_behavioral_test.dart
impact_analysis: |
  Scoped to the "+ ADD EXERCISE" button INSIDE the swap sheet only (sentinel
  __ADD_MODE__). Not affected: the swap sheet's direct exercise-select path
  (_SwapItem's onTap calls onSelect directly with no self-pop — swap_sheets.dart's
  own single pop in onSelect at line 92 is correct and untouched), the
  Delete button (line 232, its own single self-pop, untouched), and the
  active workout screen's OWN "+ ADD EXERCISE" button
  (_showExercisePickerSheet -> addExercise, a completely separate sheet with
  its own single self-pop at line 35, never double-pops).

  Critically, ActiveWorkoutData itself was NEVER destroyed by the pre-fix
  bug — it is a plain, non-autoDispose Riverpod provider, so in-progress
  state (checked sets, elapsed timer) survives navigating away. Live-verified
  2026-09-15 by navigating straight back into /train/active-workout
  (bypassing START) after reproducing the ejection: the session was still
  there, sets checked and timer still running. The founder's progress was
  actually destroyed by a SEPARATE, compounding gap: the Train tab shows no
  "resume in-progress workout" affordance, so after being ejected there the
  natural next action is tapping START again, which calls
  ActiveWorkoutNotifier.startWorkout() — an unconditional, no-confirmation
  full reset of the active workout state. This diagnose-doc fixes the
  navigation bug (the root cause that ejects the user); the missing-resume-
  affordance / no-confirmation-before-reset gap is a distinct, deliberately
  separate product question raised to the founder in the same batch, not
  bundled into this fix.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Redundant Navigator.of(ctx).pop() deleted from swap_sheets.dart's onAdd handler; flutter analyze lib/ clean (45 pre-existing info-level issues, none in touched files, zero warnings/errors)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Pure in-session Navigator + ActiveWorkoutData provider state; no Hive read/write on this path until the workout is actually completed, unaffected by this fix." }
---

## Summary

Founder-reported and jointly live-reproduced in Chrome (internal-testing
batch, session 2, 2026-09-15, Obs 5): mid active-workout, tapping SWAP on an
exercise, then "+ ADD EXERCISE" inside the swap sheet, then dismissing the
create-custom-exercise sheet without creating anything, ejected the user to
the Train tab's start-workout screen. Progress then appeared lost — the
founder subsequently tapped START again there, which is a separate,
unconditional reset (see Impact analysis) — but the navigation ejection
itself is the confirmed root cause investigated here.

## Investigation method (per CLAUDE.md §4.1)

Live reproduction was directed step-by-step by the founder and carried out
jointly:
1. Founder logged into `amar@gmail.com` (PRO) in Chrome; agent observed only,
   per founder's explicit instruction ("You just watch the Chrome, okay? I
   will do the uh, manual testing.").
2. Founder manually reproduced the ejection; reported it in real time
   ("i am swapping and clicking add exercise and then when i dont want to
   add exercise, i an back to start workout screen with all progress lost").
3. Console-log timeline correlation initially suggested a Supabase auth
   token refresh as a possible trigger (a `Refresh session` log line
   immediately preceded the navigation churn) — this was investigated and
   **superseded** once the exact mechanism below was found; the refresh may
   have been coincidental or a secondary effect of the same navigation
   churn, not the primary cause.
4. Founder then gave the agent an exact step-by-step sequence to replicate
   directly: log all 4 sets of Lat Pulldown, proceed to Dumbbell Row, tap
   SWAP, tap "+ ADD EXERCISE", then dismiss the create-custom sheet via
   pull-down without creating anything.
5. Agent replicated this exact sequence live and observed the same
   ejection, at which point the double-pop mechanism below was identified
   by reading `exercise_swap_sheet.dart` and `swap_sheets.dart` together and
   naming both the writer (the button's own self-pop) and the reader (the
   onAdd handler's redundant second pop) by file:line, per CLAUDE.md §4.1.
6. Founder corroborated with an additional concrete detail confirming
   `ActiveWorkoutData` survives the ejection: "navigating directly back into
   the active-workout route without tapping START. when you did this lat
   pull down is shown as logged, but i had clicked start workout again and
   lat pull down was not logged." — i.e. the founder had independently
   observed the same two-part mechanism (state survives navigation; state is
   destroyed only by re-tapping START) that this investigation converged on.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "swap", "add exercise", "navigation",
"pop" — no prior instance of this exact double-pop shape. The comment history
inside `swap_sheets.dart` at the fix site references bug `s1n4c0` (APK Test
#16.2), which originally ADDED the now-removed pop to solve a real but
DIFFERENT problem (the swap sheet staying mounted caused
`create.onCreated`'s SnackBar to host against a shadowed context). That fix
predates `exercise_swap_sheet.dart`'s own self-pop on the "+ ADD EXERCISE"
button, which was added independently and already solves the shadowed-context
problem on its own — making the original `s1n4c0` pop redundant, and,
combined with the self-pop, a double-pop regression. Not a recurrence of a
previously-diagnosed bug; the diagnose-doc index has no double-pop entry.

## Root Cause

Two links in the chain, confirmed by naming writer + reader by file:line
before proposing a fix (per CLAUDE.md §4.1):

1. **`ExerciseSwapSheet`'s own "+ ADD EXERCISE" button**
   (`lib/features/train/widgets/exercise_swap_sheet.dart:213-218`) —
   `onPressed` calls `Navigator.of(context).pop()` on **itself** (line 214,
   popping the swap sheet's own modal route) before invoking
   `widget.onAdd!(const SwapExerciseData(name: '__ADD_MODE__', ...))`.

2. **`_showSwapSheet`'s `onAdd` handler**
   (`lib/features/train/screens/active_workout/swap_sheets.dart:97-135`,
   pre-fix) — for the `'__ADD_MODE__'` sentinel, called
   `Navigator.of(ctx).pop()` a SECOND time, under the assumption the swap
   sheet was still on the Navigator stack. It was not — link 1 had already
   removed it. This second pop therefore removed the NEXT route down
   instead: the active workout screen's own page, ejecting the user to the
   Train tab. `_openCreateAndAutoSwap` (line 133) then opened
   `CreateCustomExerciseSheet` on top of the WRONG screen (Train tab instead
   of active workout).

Live-verified 2026-09-15: navigating straight back into
`/train/active-workout` (bypassing START) after the ejection showed the
in-progress session was STILL THERE — checked sets and the elapsed timer
intact. `ActiveWorkoutData` is a plain, non-autoDispose Riverpod provider, so
it is never destroyed by navigating away from its screen. The apparent
"progress lost" was therefore not caused by this navigation bug directly, but
by a second, compounding factor: the Train tab shows no "resume in-progress
workout" affordance, so the natural next action after being ejected there is
tapping START again — which calls `ActiveWorkoutNotifier.startWorkout()`
(`lib/features/train/providers/train_provider.dart:907`), an unconditional,
no-confirmation full reset of the active workout state. This IS what
destroyed the founder's actual logged sets.

## Fix

Deleted the redundant `Navigator.of(ctx).pop()` from
`swap_sheets.dart`'s `onAdd` handler for the `'__ADD_MODE__'` sentinel.
`_openCreateAndAutoSwap(context, ref, exerciseIndex)` is the only action
needed there — the swap sheet already popped itself in
`exercise_swap_sheet.dart`.

Not touched in this fix (deliberately, and confirmed via
`impact_analysis`): the swap sheet's direct exercise-select path (no
self-pop on `_SwapItem`, so `onSelect`'s single pop in `swap_sheets.dart` is
correct as-is), the Delete button (its own single self-pop, correct as-is),
and the active workout screen's own top-level "+ ADD EXERCISE" button
(`_showExercisePickerSheet`, a separate sheet with its own single self-pop,
never double-pops).

## Verification

`test/contracts/swap_add_exercise_double_pop_behavioral_test.dart` — 4 tests,
built around the REAL, public `ExerciseSwapSheet` widget (its "+ ADD
EXERCISE" self-pop is real app code, unmocked) inside a minimal two-route
harness standing in for [ActiveWorkoutScreen, ExerciseSwapSheet-as-modal]:

1. A Hive-free warm-up test that primes every GoogleFonts family/weight the
   sheet renders (Fraunces/h2, DM Sans/body, JetBrains Mono/mono) before any
   `path_provider` mock is installed — required because mocking
   `path_provider` (so Hive can open a box) walks GoogleFonts into its
   fetch-and-save-to-device path, where the sandboxed test-environment
   network failure surfaces as an uncaught test exception instead of the
   ordinary silent fallback degrade (same class as
   `test/contracts/exercise_plate_widgets_test.dart`'s documented fix).
2. **FIXED caller**: mirrors the fixed `swap_sheets.dart` onAdd (no extra
   pop) — tapping "+ ADD EXERCISE" inside the real `ExerciseSwapSheet`
   leaves the underlying active-workout-page marker on the Navigator stack,
   and the create-custom flow opens on top of it.
3. **MUTATION**: mirrors the pre-fix buggy caller (an extra
   `Navigator.of(ctx).pop()`) — proves the underlying page IS ejected under
   the old shape, i.e. the harness can actually detect the bug.
4. A source-grep on `swap_sheets.dart`'s onAdd handler block specifically,
   asserting it never contains `Navigator.of(ctx).pop()` and does contain
   `_openCreateAndAutoSwap(` — pins the one call site with no other public
   seam to pump through a full widget test (`part of 'screen.dart'`).

**Mutated and run** (rule 21): reintroduced `Navigator.of(ctx).pop();` before
`_openCreateAndAutoSwap(...)` in `swap_sheets.dart`'s onAdd handler (the
exact pre-fix shape). 1 of 4 tests reddened — exactly the source-grep test
(`Expected: false, Actual: <true>` — "THE BUG — a pop here double-pops...").
Tests 2 and 3 stayed green because they exercise the mechanism generically
through their own harness callback (mirroring fixed vs. buggy caller shapes
directly), not through `swap_sheets.dart`'s actual code, so they could not
see this specific mutation — the source-grep test is what pins the real call
site, exactly the same split documented for the parallel Obs 6 fix
(`docs/diagnoses/2026-09-15-swap-logging-type-outgoing-exercise-9b1e7a.md`).
Confirmed the mutation actually applied (`Navigator.of(ctx).pop()` was
present, verbatim, before the reddened run). Restored the fix — all 4 tests
passed again.

`flutter analyze lib/` run on the whole tree post-fix (required — this file
is a `part of 'screen.dart'`, and per-file analyze on a `part`-bearing
library reports clean even when a sibling part is broken): 45 pre-existing
`info`-level issues, zero in any file touched by this fix, zero warnings or
errors.

## Related

Not a recurrence of a previously-diagnosed bug (see Bug-history lookup
above), but the SAME general navigation-stack-assumption bug class as bug
`s1n4c0` (APK Test #16.2) — a caller assuming a sheet is still open when a
callee already closed it. `s1n4c0`'s own fix (adding the pop this diagnose
removes) is what introduced this bug; the two are cause and effect, not
independent.

Distinct, deliberately-unbundled follow-up raised to the founder in the same
batch: the Train tab has no "resume in-progress workout" affordance, and
`ActiveWorkoutNotifier.startWorkout()` performs an unconditional,
no-confirmation full reset when called over an in-progress session. This is
the mechanism that actually destroys logged progress once a user is ejected
by any means (this bug, backgrounding the app, etc.) — awaiting founder
decision on scope before implementation.
