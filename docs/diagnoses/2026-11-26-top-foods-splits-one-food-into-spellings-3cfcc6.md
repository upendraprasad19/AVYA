---
bug_id: 3cfcc6
date: 2026-11-26
batch: nutrition-history-v2
status: fixed
tier: full
blast_radius: feature
symptom: |
  Founder, web (2026-11-26): "In whey, I'm having three different kinds of whey: whey protein powder, whey protein isolate. Why are three different wheys being shown?" Top protein sources listed Whey protein powder, Whey protein isolate and Whey protein as three rows. Code reading: foodNameKey only lower-cased, trimmed and stripped a trailing parenthetical and "x<n>", so different names of one food never grouped.
concept: nutrition_history
sot_registry_entry: nutrition_history
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "NutritionWriteService.logMeal writes items[].name as given (unchanged)", line: 91 }
readers:
  - { file: lib/features/nutrition/services/nutrition_history.dart, method_or_widget: "foodFamilyOf + topFoods: ordered family list, whole-token match, kinds, share, concentration", line: 663 }
  - { file: lib/features/nutrition/widgets/history/history_sections.dart, method_or_widget: "HistoryTopFoods: 'Whey · 3 kinds', share %, concentration line", line: 468 }
hive_key_prefix: "nlog_ (read only, unchanged)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/nutrition_history_writer_to_reader_test.dart
ist_handling: ["not date-keyed (range filter unchanged)"]
provider_invalidations: ["none"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged."
forbidden_patterns_checked:
  - { pattern: "substring family match (eggplant -> egg, milkshake -> milk)", absent: true }
  - { pattern: "one food split into rows by spelling for a listed family", absent: true }
proposed_fix: |
  Founder D4 (plan §1, §9 U9, §11, §12): kFoodFamilies, an ordered list (multi-token first, then meats before egg, oats before milk); a family matches when its tokens appear consecutively and are not followed by "free" or "less" (a rejected match moves on); unmatched names keep foodNameKey and the plural fold. FoodStat gains kinds (trailing-s normalised), isFamily, proteinShare (of itemised protein); TopFoods gains the concentration line.
regression_test_planned: |
  nutrition_history_writer_to_reader_test.dart "v2" real-Hive case: three whey spellings logged through logMeal fold to one Whey row (3 kinds, 76 g) and proteinBySlot sums to the day. nutrition_history_v2_test.dart group "food families": order cases, negatives (eggplant, eggless, milkshake, buttermilk, whey-free), Egg/Eggs = 1 kind, share, concentration.
mutation_proof: |
  Applied by script (count confirmed 1), run, reverted. M7 chana dal pattern removed, M8 prefix match instead of whole token, M9 free/less guard off, M10 kinds without normalisation, M11 concentration threshold: each turned tests red (plan §13).
impact_analysis: |
  Top foods groups everyday families; names outside the list behave as before. Display only.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "nutrition_history.dart foodFamilyOf/topFoods; history_sections.dart HistoryTopFoods." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Real-Hive case logs through NutritionWriteService.logMeal and reads through nutritionHistoryProvider." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only derived view." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client-only." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client-only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "grep of supabase/ for foodNameKey/topFoods: none." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client-only." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client-only." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client-only." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client-only." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client-only." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client-only." }
recurrence: "Not a recurrence (no prior top-foods diagnose). Class: a grouping key narrower than the user's notion of 'the same food'."
related_bugs: []
---

# 3cfcc6 - top foods split one food by its spelling

## What happened
Three names of whey were three rows, because grouping only normalised case and trailing brackets.

## The fix
An ordered list of food families groups them; the row says "3 kinds" and the share of itemised protein.

## Not established
- Hindi and regional names beyond anda, dahi, chole, daal, dhal fall back to the old key.
