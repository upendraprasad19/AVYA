---
bug_id: b4e7f1
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A1)
status: fixed
blast_radius: feature
symptom: |
  Founder observation #1 (screenshot): the swap "UNDO" snackbar banner
  stayed visible even after the workout reached 100% completion. Investigation
  found the gap was wider than the report: the snackbar had NO explicit
  dismissal hook at all on any of its 3 real exit paths — it only ever
  disappeared via its own 5-second auto-dismiss timer.
concept: (new — no prior SoT concept; UI-lifecycle fix, not a data contract)
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, method_or_widget: _openCreateAndAutoSwap, line: 202 }
readers:
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: "_ActiveWorkoutScreenState.build (ref.listen)", line: 170 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: "_ActiveWorkoutScreenState.dispose", line: 84 }
hive_key_prefix: (n/a — UI-only, no Hive/cloud state)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: (n/a)
cloud_columns: []
contract_test_path: test/features/train/swap_undo_snackbar_dismisses_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — no user data touched, purely UI lifecycle.
forbidden_patterns_checked: []
proposed_fix: |
  Capture the ScaffoldMessengerState at snackbar-show time onto the active
  workout screen's own State (_swapUndoMessenger), threaded from the
  top-level _openCreateAndAutoSwap function (a part-of function with no
  State of its own) via a new screenState parameter. Two dismissal hooks,
  not one: (1) a ref.listen on the isComplete false->true transition
  dismisses immediately — completion does NOT unmount the screen (build()
  just switches to _buildCompleteScreen), so dispose() alone would never
  fire there; (2) dispose() dismisses as the BACKSTOP for every OTHER exit
  path (cancel dialog's context.go('/train'), and the unguarded system
  back-gesture) by construction, without enumerating each one.
regression_test_planned:
  - test/features/train/swap_undo_snackbar_dismisses_test.dart
impact_analysis: |
  Additive only: one new nullable field, one new helper method, one new
  ref.listen call, one new dispose() call, and a widened function signature
  (screenState parameter) on two already-private top-level functions with
  exactly one call site each. No existing behavior changes for any path that
  doesn't involve the swap-undo snackbar. related_bugs s1n4c0/6c2f91/d2f8a3
  are the same UI element (swap sheet) but a DIFFERENT bug class (Navigator
  modal-stack pop ordering) — not a recurrence of this fix.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/train/ — No issues found (87.9s). flutter test test/features/train/swap_undo_snackbar_dismisses_test.dart — 7/7 passed." }
mutation_proven:
  mutated: "Removed the `_dismissSwapUndoSnackBar();` call from dispose() in screen.dart, confirmed applied by reading the file."
  result: "Ran flutter test test/features/train/swap_undo_snackbar_dismisses_test.dart: RED — 'dispose() calls the dismiss backstop' failed (source-grep no longer found the call in the dispose() block), 6 passed / 1 failed. Reverted the mutation; re-ran: GREEN, 7/7 passed."
  confirmed_applied: "Read the file (Edit tool's own before/after) to confirm the removed line matched the intended mutation both times."
---

## Summary

The swap-undo snackbar had no explicit dismissal hook on any of its 3 real exit
paths (workout completion, the cancel dialog, and the unguarded system
back-gesture) — it only ever disappeared via its own 5-second auto-dismiss
timer, so a founder who left the screen (by any means) within that window kept
seeing it.

## Root cause

`_openCreateAndAutoSwap` (swap_sheets.dart) shows the snackbar via
`ScaffoldMessenger.of(context)` but never retains a reference to dismiss it
later — nothing in the screen's lifecycle ever calls
`hideCurrentSnackBar()`. Investigation additionally found the cancel dialog
navigates via `context.go('/train')` (GoRouter), not `Navigator.pop`, and the
screen has no `PopScope`/`WillPopScope` guarding the system back-gesture — an
enumeration-based fix keyed only to `Navigator.pop` would have missed both.

## Fix

Lifecycle-based rather than navigation-trigger-based: the `ScaffoldMessengerState`
is captured on the screen's own State at show-time. A `ref.listen` on the
`isComplete` false→true transition dismisses it immediately (completion
doesn't unmount the screen). `dispose()` dismisses it as the backstop for
every path that DOES unmount the screen — covering the cancel dialog and the
back-gesture by construction, not by enumeration.

## Verification

- New behavioral test mirrors the exact mechanism in a minimal harness (the
  real widgets are private with no public seam to pump) and drives all 3 exit
  paths, asserting the SnackBar is gone after each.
- A companion source-grep group pins that the real files are actually wired
  this way (dispose() calls the backstop; the ref.listen fires on the
  completion transition; the messenger is threaded through both functions).
- Mutation proof: removed the dispose()-backstop call — the source-grep test
  caught it by name; reverted, 7/7 green again.
- `flutter analyze lib/features/train/` — no issues (full-tree analyze, not
  per-file, since these files are `part of screen.dart`).

## Files changed

- Modified: `lib/features/train/screens/active_workout/screen.dart`
- Modified: `lib/features/train/screens/active_workout/swap_sheets.dart`
- Created: `test/features/train/swap_undo_snackbar_dismisses_test.dart`
- Created: this diagnose-doc.
