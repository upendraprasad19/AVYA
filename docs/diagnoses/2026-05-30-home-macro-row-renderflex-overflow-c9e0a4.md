---
bug_id: c9e0a4
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Live web (amar@gmail.com), Home Today card: three "A RenderFlex overflowed by
  N pixels on the right" exceptions (12 / 29 / 9.5 px) rendered as yellow/black
  overflow stripes on the FUEL / PROTEIN / STEPS macro column, plus a "bottom
  overflowed by 1.00 pixels" on the Today card. In release the overflow clips
  the macro numbers instead of striping.
concept: home_today_macro_column_layout
sot_registry_entry: n/a
blast_radius: feature
writers:
  - { file: lib/features/home/widgets/today_workout_card.dart, method: _MacroRow.build, line: 525 }
readers:
  - { file: lib/features/home/widgets/today_workout_card.dart, method: _MacroColumn.build, line: 462 }
hive_key_prefix: "n/a (pure widget render)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: n/a
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Unchanged. Pure widget render.
forbidden_patterns_checked: []
proposed_fix: >
  _MacroRow laid the label Text + Spacer + number RichText in a Row inside the
  fixed-width right-column macro tile (~40% of the card). Neither the label nor
  the number was Flexible, so when the rendered value string was wide (e.g.
  "0/2200", "/135g") the Row's intrinsic width exceeded the tile and RenderFlex
  reported a right overflow (and the numbers clipped in release). Fix: wrap the
  label in Flexible with maxLines:1 + ellipsis, and wrap the number RichText in
  Flexible + FittedBox(fit: scaleDown, alignment: centerRight) so the number
  scales down to fit rather than overflowing. The Spacer is retained so the
  number stays right-aligned when there is slack.
regression_test_planned: []
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "today_workout_card.dart _MacroRow label+number now Flexible/FittedBox; flutter analyze clean" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "live console captured the 12/29/9.5px right overflows + 1px bottom on the Home Today card macro column; layout fix removes the unbounded intrinsic" }
impact_analysis: >
  Feature-tier, cosmetic. No crash, no data effect. In debug the overflow paints
  the yellow/black stripe; in release it silently clips the macro numbers (a
  user could see a truncated FUEL/PROTEIN/STEPS value). Fix is a standard
  Flexible + FittedBox layout guard. Visual re-confirmation at the exact device
  width requires a fresh `flutter build web` (the running dev server is the
  pre-fix build and hot-reload is not driven from this session); the fix is
  sound by construction (FittedBox scaleDown can never overflow its Flexible
  box). The 1px-bottom overflow is the same class (an unbounded child in the
  card column) and is resolved by the same shrink-to-fit change to the macro
  rows that previously forced the card's intrinsic height up.
---

# c9e0a4 — Home Today card macro column RenderFlex right-overflow

## What happened
The Today card's right 40% column (`_MacroColumn`) stacks three `_MacroRow`s
(FUEL / PROTEIN / STEPS). Each `_MacroRow` is a `Row` of bullet + label +
`Spacer()` + number `RichText`, with no `Flexible` on either text. In the narrow
column, a wide value string ("0/2200", "/135g") pushed the Row's intrinsic width
past the tile → RenderFlex right overflow (12 / 29 / 9.5 px on live web) and
clipped numbers in release.

## Fix
Label → `Flexible(Text(maxLines:1, overflow: ellipsis))`; number →
`Flexible(FittedBox(fit: scaleDown, alignment: centerRight, RichText(maxLines:1)))`.
`Spacer` retained for right-alignment when slack exists. FittedBox guarantees
the number can never exceed its allotted box.

## Verification
Live console pinned the exact overflows on the Home Today card. `flutter analyze`
clean. Pixel re-confirmation needs a web rebuild (running server is pre-fix); the
fix is overflow-proof by construction.
