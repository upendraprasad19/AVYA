---
bug_id: s1n4c0
date: 2026-05-18
batch: APK Test #16.2 observations (2026-05-18)
status: shipped
symptom: |
  During an active workout, the user opened the swap sheet on an exercise,
  tapped "+ ADD EXERCISE" and created "Barbell Jump Squats" via the inline
  CreateCustomExerciseSheet. The "Swapped X to Y / UNDO" snackbar appeared
  at the bottom of the screen and never auto-dismissed despite the
  5-second duration. The user had to fully close and reopen the app to
  clear it.
concept: swap_undo_snackbar_modal_stack
sot_registry_entry: workout_schedule_service_routes_through_write_service
writers:
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: _openCreateAndAutoSwap.onCreated, line: 811 }
readers:
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: ScaffoldMessenger emission point (snackbar host), line: 809 }
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: outer modal route still mounted when onCreated fires, line: 1 }
  - { file: lib/features/train/widgets/create_custom_exercise_sheet.dart, method_or_widget: pops self then fires onCreated, line: 94 }
hive_key_prefix: "n/a — UI lifecycle bug, no Hive write"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/features/train/swap_undo_snackbar_dismisses_test.dart
ist_handling: []
provider_invalidations: [todayWorkoutProvider, currentPlanProvider, calendarWeekProvider]
telemetry_op_types:
  success: [swap_exercise_via_create_custom]
  failure: [swap_undo_snackbar_orphaned]
cross_account_guard: "n/a — UI-only, no per-user storage touched by this path"
forbidden_patterns_checked:
  - "ScaffoldMessenger.of(ctx).showSnackBar inside a child modal route without first popping intermediate sheets"
proposed_fix: |
  The outer ExerciseSwapSheet at active_workout_screen.dart line 705 stays
  mounted when the user taps "+ ADD EXERCISE" — the onAdd handler at line
  749 directly opens CreateCustomExerciseSheet via _openCreateAndAutoSwap
  WITHOUT popping the swap sheet first. The picker-path mirror at line
  733 (Navigator.of(ctx).pop after swap) is the correct pattern; the add-
  exercise path skipped it.

  When CreateCustomExerciseSheet pops itself at line 94 and then fires
  widget.onCreated, the active modal route on top of the navigator is
  still the swap sheet. ScaffoldMessenger.of(context) at line 809 resolves
  to a context that is shadowed by an active ModalRoute, so the snackbar
  is enqueued but its dismiss timer interacts with the modal stack such
  that, on Android, the SnackBarController never receives a status update
  to start its reverse animation. The snackbar visually persists until the
  scaffold messenger is rebuilt (app restart).

  Fix is single-line: pop the swap sheet at the start of the onAdd
  handler before invoking _openCreateAndAutoSwap. The swap sheet's
  context is captured in the showModalBottomSheet builder at line 706, so
  popping it via Navigator.of(swapSheetCtx).pop() is safe before opening
  the create sheet. This mirrors the onSelect picker path.
regression_test_planned:
  - widget test simulating the full _openCreateAndAutoSwap flow, asserting that the snackbar IS shown and IS auto-dismissed within 5500ms
  - source-grep contract test forbidding _openCreateAndAutoSwap from being called inline from a builder whose enclosing modal is not popped first
---
# Body

## Why the user saw it

The user explicitly confirmed: tapped "+ ADD EXERCISE" inside the swap
sheet and typed "Barbell Jump Squats" rather than picking from the
suggested list. That places them on the `_openCreateAndAutoSwap` path at
`active_workout_screen.dart:761-837` which IS the only Dart site emitting
the "Swapped X to Y / UNDO" snackbar literal anywhere in the codebase
(confirmed by `Grep "Swapped"` across `lib/`).

## Why the 5s timer did not fire

`SnackBar.duration` schedules a reverse-animation kick via the
`SnackBarController` inside ScaffoldMessenger. When the host scaffold's
messenger is shadowed by an active `ModalRoute` (here: the still-mounted
`ExerciseSwapSheet`), Flutter's framework correctly enqueues the
snackbar but the dismiss callback is wired against the route stack's
animation lifecycle. On Android with `SnackBarBehavior.floating` we have
seen this pattern leave the snackbar in a "shown but never told to
dismiss" state when the underlying route stack pops the parent modal
asynchronously after the user tapped save.

The simpler-and-correct fix is to never let this race happen: pop the
swap sheet before opening the create sheet, so the snackbar is hosted
against a scaffold with no intermediate modal route.

## Why this was missed in code review

The picker-path at `:713-734` correctly pops its host sheet at `:733`
before completing. The add-exercise path at `:738-752` calls
`_openCreateAndAutoSwap` without the analogous pop. The path is reached
only when a user (a) opens swap, (b) taps "+ ADD EXERCISE", (c) types a
name that doesn't clash with any in-library exercise. Test #1 introduced
this flow and the manual-test smoke at that time did not catch the
snackbar lifecycle issue because the tester never waited >5s to see
auto-dismissal — they pressed UNDO or moved on.

## Open question for founder

Is the user okay with the snackbar moving from 5s to 4s? Material 3
floating snackbars are best-practice between 3-7s. We're keeping 5s.
