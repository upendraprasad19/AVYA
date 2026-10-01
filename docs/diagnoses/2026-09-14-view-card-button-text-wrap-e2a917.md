---
bug_id: e2a917
date: 2026-09-14
batch: Internal-testing observation batch (Obs 3)
status: fixed
blast_radius: feature
symptom: |
  Founder-reported screenshot from internal testing: on the Home "Today" card's
  completed state, the "VIEW CARD →" OutlinedButton is visually deformed — the
  stadium pill is tall and misshapen instead of a clean single-line pill. Root
  cause is text wrap, not a navigation/destination bug (the button correctly
  opens WorkoutReceiptSheet, per workout_receipt_rendering SoT).
concept: workout_receipt_rendering
sot_registry_entry: |
  Not applicable — this is a pure layout/overflow fix on an existing button,
  not a writer-reader contract change. onViewCard still calls the same handler.
writers:
  - { file: lib/features/home/widgets/today_workout_card.dart, method_or_widget: "_HeroCard completed-state Row (VIEW CARD OutlinedButton)", line: 358 }
readers:
  - { file: lib/features/home/widgets/today_workout_card.dart, method_or_widget: "Text('VIEW CARD →')", line: 368 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/widgets/today_workout_card_view_card_button_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure UI layout, no data access."
forbidden_patterns_checked:
  - { pattern: "Text with no overflow handling inside an Expanded/StadiumBorder button at a squeezed width", absent: true }
proposed_fix: |
  Add maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis to the
  'VIEW CARD →' Text widget so it stays on one line and ellipsizes rather than
  wrapping and deforming the StadiumBorder pill on a narrow card width.
regression_test_planned:
  - test/widgets/today_workout_card_view_card_button_test.dart
impact_analysis: |
  Cosmetic-only fix. No behavior change to onViewCard (still opens
  WorkoutReceiptSheet). No writer/reader drift — verified by reading the
  actual widget code (see feedback_mistake_unverified_done_claims.md #22,
  logged this same session after initially guessing the button's destination
  without reading source).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Text overflow handling added at today_workout_card.dart:368-371; flutter analyze clean." }
---

## Summary

Founder screenshot (internal-testing batch, 2026-09-14) showed the completed-state
"VIEW CARD →" button on the Home "Today" card rendered as a tall, misshapen pill
instead of a clean stadium shape.

## Root Cause

`lib/features/home/widgets/today_workout_card.dart:358-378` — the completed-state
row is `DONE chip + SizedBox(8) + Expanded(OutlinedButton(StadiumBorder, Text('VIEW CARD →')))`.
The button gets whatever width remains after the DONE chip, and the `Text` had no
`maxLines`/`overflow`/`softWrap` handling. On a squeezed card width (this app's
two-column 50/50 hero/macro split leaves limited room in the hero column), "VIEW
CARD →" wraps onto two lines inside the stadium pill, deforming it.

Two writer/reader guesses were made and rejected before reading the code: first
that VIEW CARD opened exercise details, then that it opened an Instagram share
card. Both were wrong — it correctly opens `WorkoutReceiptSheet` (the workout
"receipt"), per the `workout_receipt_rendering` SoT entry in
`lib/features/home/CLAUDE.md`. The bug is purely the button's text layout, not
its destination.

## Fix

Added `maxLines: 1`, `softWrap: false`, `overflow: TextOverflow.ellipsis` to the
`Text('VIEW CARD →')` widget so it stays on a single line and ellipsizes under
tight width rather than wrapping.

## Verification

`test/widgets/today_workout_card_view_card_button_test.dart` renders the
completed state at a 400px width (the width at which the pre-fix button
overflowed) and asserts:
- No exception/overflow error during layout.
- `Text.maxLines == 1`, `softWrap == false`, `overflow == TextOverflow.ellipsis`.
- Rendered text height stays within a single-line bound.

**Mutated and run** (rule 21): reverted the three added Text properties —
test failed at the `maxLines` assertion (`Expected: 1, Actual: <null>`).
Restored the fix — test passed. 1 test, 1/1 reddened by the mutation.

## Related

None — first instance of this specific overflow; not a recurrence of a named
bug class. See `feedback_mistake_unverified_done_claims.md` #22 for the
process lesson (verify UI behavior claims against source, not screenshots).
