---
bug_id: 7e3c91
date: 2026-06-01
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: feature
symptom: >
  On the Nutrition tab's TODAY'S SUMMARY card (driven live as amar), the macro
  rows showed Flutter's debug RenderFlex stripe banner ("RIGHT OVERFLOWED BY N
  PIXELS", rendered vertically on the right edge) and the values were clipped +
  squished into the labels ("PROTEIN451 / 535g", "WATER2103 / ...25ml"). The
  right-hand macro column sits beside a fixed 110px calorie ring, so wide values
  exceed its width.
concept: nutrition_summary_macro_row_layout
sot_registry_entry: not_applicable (pure UI layout on the Nutrition screen — no Hive/cloud writer/reader contract)
writers:
  - lib/features/nutrition/screens/nutrition_screen.dart _macroRow (renders one macro row: label + "current / target+suffix" value in a Row; FIX wraps the label in Flexible + ellipsis)
readers:
  - lib/features/nutrition/screens/nutrition_screen.dart the TODAY'S SUMMARY calorie card body (calls _macroRow 5× for PROTEIN / CARBS / FAT / FIBER / WATER inside an Expanded column next to the 110px WardRing)
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (UI layout — no Hive key)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable (no data path — layout-only fix)
contract_test_path: test/contracts/nutrition_summary_macro_row_no_overflow_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable (no state mutated — pure render fix)
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (no data read/written; the overflow was merely TRIGGERED by the magnitude of amar's data, the fix is layout-only)
forbidden_patterns_checked:
  - "Row(mainAxisAlignment: spaceBetween) with two unconstrained Text children that can exceed the available width → RenderFlex overflow — eliminated: the label Text is wrapped in Flexible with maxLines:1 + TextOverflow.ellipsis; pinned by test/contracts/nutrition_summary_macro_row_no_overflow_test.dart."
proposed_fix: >
  In `_macroRow`, wrap the LABEL Text in `Flexible` with `maxLines: 1` +
  `overflow: TextOverflow.ellipsis`, and add a `SizedBox(width: 8)` gutter before
  the value. Under width pressure the label ellipsizes (it is a fixed known
  string) while the numeric value — the actual data — keeps its full width and
  right alignment, so the Row can never overflow. The value alone is far narrower
  than the column, so it never overflows on its own. Normal-magnitude values
  render unchanged (nothing ellipsizes).
regression_test_planned: >
  test/contracts/nutrition_summary_macro_row_no_overflow_test.dart (3/3,
  comment-stripped source-grep scoped to the `_macroRow` method body): pins
  (1) the label is wrapped in `Flexible`, (2) it uses `TextOverflow.ellipsis` +
  `maxLines: 1`, (3) the value `'$current / $target$suffix'` is still rendered in
  full. Behavioral proof is the live observation: the RenderFlex stripe banner
  was present pre-fix on amar's TODAY'S SUMMARY card and is removed by wrapping
  the overflowing child (the standard Flutter Flexible-ellipsis idiom).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "nutrition_screen.dart _macroRow label wrapped in Flexible + maxLines:1 + TextOverflow.ellipsis; flutter analyze on the file = exit 0 / No issues; test 3/3 pass" }
  - { tier: 2, layer: hive_local_state, status: not_applicable, evidence: "no Hive read/write — pure layout fix; the displayed values come from the existing nutritionSummary provider unchanged" }
impact_analysis: >
  Feature blast radius — a render-only fix on the Nutrition tab's TODAY'S SUMMARY
  card; no data, no cross-account, no platform behavior changes. The overflow
  triggers whenever a macro row's "current / target + suffix" value is wide
  enough to exceed the narrow right column beside the 110px ring — that includes
  a realistic 4-digit WATER row ("2103 / 3125ml") for ANY user, not just the
  sim-inflated macros that surfaced it live on amar. The fix is conservative and
  backward compatible: normal-magnitude values render identically (the Flexible
  label only ellipsizes when it would otherwise overflow), and the numeric value
  is never truncated. Found live via the Claude-in-Chrome E2E (real CanvasKit
  pixels) during the derive-only AI-coach batch's cross-surface verification.
---

# Nutrition TODAY'S SUMMARY macro rows overflowed (RenderFlex RIGHT OVERFLOW)

## What happened

On the Nutrition tab (live, amar), the TODAY'S SUMMARY card's macro rows
(PROTEIN / CARBS / FAT / FIBER / WATER) showed the debug RenderFlex stripe
banner and clipped/squished text — e.g. "PROTEIN451 / 535g", "WATER2103 /
...25ml". The macro column is an `Expanded` beside a fixed **110px** calorie
ring, and each row was a `Row(spaceBetween)` of two **unconstrained** `Text`
children (label + `'$current / $target$suffix'`). When the combined intrinsic
width exceeds the column, `spaceBetween` has no slack to distribute, so the
children butt together and the right one clips → overflow.

## Root cause

Neither child was wrapped in `Flexible`/`Expanded`, so the Row could not shrink
to fit. Wide values overflow: amar's sim-inflated macros surfaced it, but a
realistic 4-digit water row ("2103 / 3125ml") would do the same for a normal
user.

## Fix

Wrap the LABEL in `Flexible(maxLines: 1, overflow: TextOverflow.ellipsis)` and
add an 8px gutter. The label (a fixed known string) ellipsizes under pressure;
the numeric value keeps full width + right alignment, so the data is never
hidden and the Row can never overflow. Normal values render unchanged.

## Verification

- `flutter analyze lib/features/nutrition/screens/nutrition_screen.dart` → exit 0.
- `test/contracts/nutrition_summary_macro_row_no_overflow_test.dart` → 3/3.
- Live: the stripe banner was visible on amar's TODAY'S SUMMARY pre-fix; the
  standard Flexible-ellipsis idiom removes it (visual re-confirm on next web/APK
  rebuild — the running debug web build does not hot-recompile).

## Lesson / class

Any `Row` whose children include free-text or numeric values that can grow
(counts, large numbers, user content) MUST wrap at least one child in
`Flexible`/`Expanded` (+ `ellipsis`) — `spaceBetween` alone does not prevent
overflow, it just hides the slack. Prefer ellipsizing the LABEL and preserving
the VALUE when the value is the data. Live real-pixel E2E (Claude-in-Chrome)
catches these debug-only RenderFlex banners that unit tests miss.

## See also

- `lib/features/nutrition/screens/nutrition_screen.dart` (`_macroRow`)
- `test/contracts/nutrition_summary_macro_row_no_overflow_test.dart`
- Sibling RenderFlex pass: APK Test profile overflow sweep (task D-profile, 2026-05-30).
- `.claude/skills/e2e-sim-testing/SKILL.md` (the venue that surfaced it)
