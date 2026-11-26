---
bug_id: a9d5c3
date: 2026-11-25
batch: nutrition-history
status: fixed
tier: full
blast_radius: account
symptom: |
  Found in the Nutrition History brainstorm by reading the code and shown by a behavioral test, NOT observed on a device: after a target change (Edit Profile's Save, the coach goal switch, or a weigh-in that moves the targets) the two weekly cards under INSIGHTS & TRENDS keep the OLD calorie and protein target in their "Target:" line until the next meal log or the day rollover, while the daily card above them already shows the new one.
concept: nutrition_total_calories
sot_registry_entry: nutrition_total_calories
writers:
  - { file: lib/features/profile/providers/profile_surface_invalidation.dart, method_or_widget: "profileDerivedSurfaceProviders: the one list the three target-changing doors invalidate; weeklyNutritionProvider was not in it", line: 31 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "WeeklyNutritionNotifier.build: reads the targets from the profile once per build", line: 1669 }
hive_key_prefix: "none (userBox['profile'])"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/weekly_nutrition_follows_target_change_behavioral_test.dart
ist_handling: ["not date-keyed"]
provider_invalidations: ["weeklyNutritionProvider added to profileDerivedSurfaceProviders (invalidated by edit_profile_screen._save, tool_dispatcher _executeSwitchGoal and WeightLogNotifier.logWeight through invalidateProfileDerivedSurfaces)"]
telemetry_op_types:
  success: ["none"]
  failure: ["profile_surface_invalidation (existing, unchanged)"]
cross_account_guard: "Unchanged."
forbidden_patterns_checked:
  - { pattern: "a per-door ref.invalidate(weeklyNutritionProvider) added at one of the three callers only", absent: true }
proposed_fix: |
  weeklyNutritionProvider joins profileDerivedSurfaceProviders, the single list all three target-changing doors already invalidate. The new nutritionHistoryProvider needs no entry: it watches macroTargetsProvider, which is in the list.
regression_test_planned: |
  test/contracts/weekly_nutrition_follows_target_change_behavioral_test.dart (real Hive): read the weekly data (2540), change the stored targets, assert the provider still holds 2540 with no refresh, run invalidateProfileDerivedSurfaces, assert 2200 / 150. test/contracts/profile_surface_invalidation_test.dart pins the list (7 entries).
mutation_proof: |
  M12 (the entry removed from the list), applied (one site) and reverted by nh_mutate.py; result in docs/audit/nutrition-history.closure.yaml.
impact_analysis: |
  One more provider rebuilt per profile-derived refresh (one pass over the nutrition box, the same pass every meal log already triggers). No write, no sync.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "profile_surface_invalidation.dart:31; whole-project analyze has no warning." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The regression test changes the stored profile in the real userBox and reads the provider before and after the shared refresh." }
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
recurrence: "Recurrence of the class 'a Hive-reading provider missing from a refresh list': bae4dd (this same provider was missing from the day-rollover list), 9c8958, b3c9d4, c2f7d1. Same known-good fix: add it to the shared list at the source, not at one caller."
related_bugs: [bae4dd, 9c8958, b3c9d4, c2f7d1]
---

# a9d5c3 - weekly Insights cards keep the old target after a target change

## What happened
`WeeklyNutritionNotifier` reads the profile's targets directly and was in no profile refresh list.

## The fix
One entry in `profileDerivedSurfaceProviders`.

## Not established
- Not observed on a device.
