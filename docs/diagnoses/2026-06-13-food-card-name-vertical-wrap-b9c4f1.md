---
bug_id: b9c4f1
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: feature
symptom: >
  Obs#7 (live web E2E, cosmetic): on the AI food-analysis result card
  (ai_breakdown_card._buildItemRow), item names ("Boiled Eggs", "Chicken Breast
  100g") rendered VERTICALLY — one character per line. The name Text sits in an
  Expanded > Column, but the same Row also holds five fixed-width macro columns
  (PRO/CARB/FAT/FIBER/KCAL) + a 28px edit button; at a narrow frame those fixed
  children consumed the row width, squeezing the Expanded (name) to ~0 width, so
  the unbounded name wrapped one char per line. The macros row itself rendered
  fine.
concept: expanded_starved_by_fixed_siblings
sot_registry_entry: not_applicable
contract_test_path: test/contracts/food_card_name_single_line_test.dart
writers: >
  lib/features/nutrition/widgets/ai_breakdown_card.dart — the item name +
  quantity Text now carry maxLines: 1 + TextOverflow.ellipsis.
readers: >
  AI food-analysis result card item rows (food_logger_section / scan result).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "Unbounded item-name Text inside a width-starved Expanded → vertical char-per-line wrap. Now maxLines: 1 + ellipsis. Pinned by test/contracts/food_card_name_single_line_test.dart."
proposed_fix: >
  Add maxLines: 1 + overflow: TextOverflow.ellipsis to the item name (and
  quantity) Text. When the Expanded is squeezed, the name now truncates
  horizontally with an ellipsis instead of rendering as a vertical character
  column. Full name remains available via the edit sheet.
regression_test_planned: >
  test/contracts/food_card_name_single_line_test.dart — source-grep (comment-
  stripped): the item.name Text in ai_breakdown_card declares maxLines: 1 +
  TextOverflow.ellipsis.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "name + quantity Text now single-line+ellipsis; flutter analyze clean; food_card_name_single_line_test green" }
impact_analysis: >
  Feature/cosmetic blast radius, narrow-frame (web mobile-frame) impact; may not
  reproduce on a real Android device (wider effective layout). The fix is the
  standard Flutter remedy for a starved Expanded and is harmless at any width.
  Note carried to device verification: if a real device still shows the name too
  narrow to read, a follow-on responsive 2-row layout (macros below the name)
  would be the next step — but the vertical-char-wrap pathology the founder
  reported is resolved by this change.
---

# Food-analysis item name wraps one char per line (b9c4f1)

## What happened
`_buildItemRow` puts the name in `Expanded > Column > Text`, beside 5 fixed-width
macro columns + an edit button. At a narrow frame the fixed siblings starve the
Expanded to ~0 width and the unbounded name wraps vertically (one char per line).

## Fix
`maxLines: 1` + `overflow: TextOverflow.ellipsis` on the name (and quantity) Text
→ horizontal ellipsis instead of a vertical character column.

## See also
- lib/features/nutrition/widgets/ai_breakdown_card.dart
- test/contracts/food_card_name_single_line_test.dart
