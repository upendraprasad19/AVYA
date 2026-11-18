---
bug_id: 2d9f4b
date: 2026-11-18
batch: diet-grams-toggle (OI-517)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  The Diet chart's Portions text showed "1. cups (255 g)" for a scaled serving: `scaleServingDesc('0.667 cup (170 g)', 1.5)`. `formatServingQty` formatted 1.0005 as `toStringAsFixed(2)` = "1.00" and stripped only the zeros (`0+$`), leaving "1.", and the plural rule (`newQty > 1`) made it "cups" for a quantity of one. Found by the OI-517 plan review (the Grams bracket reuses this text), then reproduced by running the real function: 0.667 cup x 1.5 -> "1. cups (255 g)", x3 -> "2. cups (510 g)". Only descriptions whose quantity is not a multiple of a quarter reach the two-decimal branch (the Amul Dahi Yogurt row, 0.667 cup).
concept: diet_serving_desc_scaling
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/nutrition/services/curated_diet_plan_generator.dart, method_or_widget: "formatServingQty (two-decimal branch) and scaleServingDesc (plural rule)", line: 592 }
readers:
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: "meal row text from the scaled item.servingDesc", line: 704 }
  - { file: lib/features/nutrition/widgets/diet_plan_swap_sheet.dart, method_or_widget: "alternative row text", line: 89 }
hive_key_prefix: none
hive_key_formula: "not applicable: display text only, the saved plan stores serving_desc as shown and is not rewritten"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/serving_qty_format_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: a pure formatter."
forbidden_patterns_checked:
  - { pattern: "a quantity printed with a trailing dot", absent: true }
proposed_fix: |
  `formatServingQty`: strip the zeros AND a dangling dot (`\.?0+$`). `scaleServingDesc`: pluralise only when the new quantity exceeds one by more than 0.005 (so 1.0005 reads "1 cup"). Quarters and whole numbers are untouched.
regression_test_planned: |
  test/contracts/serving_qty_format_test.dart: 1.0005 -> "1", 2.004 -> "2", 0.333 -> "0.33", quarters and wholes unchanged, and the real row (0.667 cup (170 g)) at 1.5 / 2 / 3.
mutation_proof: |
  Rule 21, backup/mutate/run/restore. M1 dot-strip reverted to `0+$`: 2 tests RED. M2 plural slack removed (`newQty > 1`): 1 test RED. Both restored; the three files (this test, the label test over 1444 rows x 5 multipliers, the curated plan test) pass together (44).
impact_analysis: |
  Display text only. A previously saved plan keeps the text it was saved with (the row is not rewritten); a regenerated or re-scaled serving reads correctly. No stored value changes meaning.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "formatServingQty and scaleServingDesc fixed; new test passes; curated_diet_plan_test and diet_serving_label_test still pass." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No stored value changes." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Not a recurrence: 83ac8a (the curated catalog) introduced scaleServingDesc and only mutates it (M7); no earlier diagnose names formatServingQty or a trailing dot (docs/diagnoses/INDEX.md is a local build and was absent; grepped docs/diagnoses for both names)."
related_bugs: [83ac8a]
---

# 2d9f4b - a scaled serving printed "1. cups"

## What happened
`formatServingQty` has a quarter branch (`1/2`, `1 1/4`) and a two-decimal branch for everything else. The two-decimal branch formatted 1.0005 as "1.00" and removed only the trailing zeros, so the dot stayed. The plural rule then compared the raw 1.0005 with 1 and pluralised. One catalog row (0.667 cup) reaches it. The OI-517 Grams label puts this text inside brackets, so it is fixed at the source.
