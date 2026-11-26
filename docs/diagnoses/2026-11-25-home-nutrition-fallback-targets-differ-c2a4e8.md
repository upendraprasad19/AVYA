---
bug_id: c2a4e8
date: 2026-11-25
batch: nutrition-history
status: fixed
tier: full
blast_radius: account
symptom: |
  Found in the Nutrition History brainstorm by reading the code, NOT observed on a device: for a profile with no complete stored target pack, Home's nutrition card and the Nutrition tab show different targets. Nutrition recomputes from weight, height and gender (or, with no inputs, shows 2400 kcal / 184 g protein / 280 g carbs / 80 g fat); Home used its own per-field defaults 2000 / 120 / 250 / 65 and never recomputed. A profile holding only daily_calories 2540 plus its inputs showed 2540 kcal with 120 g protein on Home and 2602 kcal with 128 g protein on Nutrition.
concept: diet_strategy_targets
sot_registry_entry: diet_strategy_targets
writers:
  - { file: lib/features/profile/services/profile_write_service.dart, method_or_widget: "updateProfile / patchProfile / patchProfileWith: the only writers of the stored target pack", line: 68 }
readers:
  - { file: lib/core/utils/nutrition_targets_resolver.dart, method_or_widget: "resolveNutritionTargets: stored pack, else recompute, else the last resort; then the diet strategy", line: 120 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "NutritionSummaryNotifier.build: now calls the resolver", line: 653 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "_resolveNutritionTargets: a thin adapter over the resolver", line: 55 }
hive_key_prefix: "none (userBox['profile'] fields daily_calories, protein_grams, carb_grams / carbs_grams, fat_grams)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/weekly_nutrition_follows_target_change_behavioral_test.dart
ist_handling: ["not date-keyed"]
provider_invalidations: ["none changed; Home keeps its PRO and restore-tick watches behind DietStrategyFlags.enabled"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged: the '<anon>' early return still precedes the profile read."
forbidden_patterns_checked:
  - { pattern: "a second fallback table for shown targets outside nutrition_targets_resolver.dart", absent: true }
  - { pattern: "getActiveTargetOverride / _applyCalorieOverride (the removed one-day override readers)", absent: true }
proposed_fix: |
  The resolution moved verbatim into lib/core/utils/nutrition_targets_resolver.dart. Nutrition keeps its map shape through a thin adapter; Home calls the resolver in place of its own reads and defaults. For a profile WITH a complete stored pack the numbers are unchanged on both (pinned by a preservation test written before the move). The readers of the removed one-day calorie override (its only writer, a coach tool, was removed on 2026-05-31) were deleted in the same change, so the resolver has no override step.
regression_test_planned: |
  test/contracts/weekly_nutrition_follows_target_change_behavioral_test.dart: five profiles (stored pack, restored pack with plural carbs, inputs only, partial pack with inputs, nothing) on real Hive; Home's four targets equal literal expectations AND equal macroTargetsProvider. test/contracts/nutrition_targets_resolver_preservation_test.dart: 24 literal cases, green before and after the move.
mutation_proof: |
  M18 (Home falls back to its own 250 g carb default when the profile has no carb_grams) and M5 (the resolver ignores the stored pack), each applied (one site) and reverted by nh_mutate.py; results in docs/audit/nutrition-history.closure.yaml.
impact_analysis: |
  Home's nutrition card targets change ONLY for a profile without a complete stored pack (a new or partly restored account). An existing pin, diet_strategy_targets_writer_to_reader_test "9: an incomplete stored pack", recorded Home's own 250 g default and was updated to the shared 280 g with the reason. The coach snapshot keeps its own 0 defaults (unchanged, out of scope: it feeds the AI prompt).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "home_provider.dart:640-658, nutrition_provider.dart:46-100, nutrition_targets_resolver.dart; whole-project analyze has no warning." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The regression test writes the profile into the real userBox and reads both providers." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client-only change: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
recurrence: "Recurrence of the class 'a second computation of the same target drifting from the canonical one': c7a1f5 and OBS-11 (Home and Nutrition disagreed on a restored profile because one read carb_grams and the other carbs_grams). Same known-good fix, taken one step further: one function instead of two aligned copies."
related_bugs: [c7a1f5]
---

# c2a4e8 - Home and Nutrition used different fallback targets

## What happened
Two readers each resolved the shown targets, with different fallbacks.

## The fix
One resolver in `lib/core/utils/nutrition_targets_resolver.dart`, used by Nutrition, Home, the weekly cards, the History screen and the target history.

## Not established
- Not observed on a device; how many accounts lack a complete stored pack was not measured (all accounts are test accounts before launch).
