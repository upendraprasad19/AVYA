---
bug_id: b1d2a8
date: 2026-11-22
batch: oi348-walk-fixes Landing 1a-i (B1 hotfix + P4)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk A5 part 2 (AAB 1.0.0+50, Upendra, 2026-11-22): every meal logged in the last 24 h, and the day total, showed twice on the Nutrition screen of the phone AND the web app (breakfast 1033 kcal shown as 2066), with an extra card named after the slot ("Lunch"); it doubled again after a refresh or a cold start. The cloud held each meal once with the right totals.
concept: nutrition_pull_copy_cleanup
sot_registry_entry: nutrition_pull_copy_cleanup
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_pullNutritionLogs (the cross-channel pull's nutrition leg, put under the cloud UUID)", line: 2696 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "whole-box walk by date (day total)", line: 440 }
  - { file: lib/core/services/nutrition_read_service.dart, method_or_widget: "whole-box walk", line: 120 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "whole-box walk", line: 794 }
hive_key_prefix: "none (the copy is keyed by the raw cloud row id); the real row is nlog_"
hive_key_formula: "nutritionBox.put(map['id'] as String, {...map, 'source': map['source'] ?? <dropped channel label>})"
sync_methods: [pullRecentCrossChannelLogs, _pullNutritionLogs]
restore_methods: [_restoreNutritionLogs]
cloud_table: nutrition_logs
cloud_columns: [id, user_id, date, meal_type, total_calories, total_protein, total_carbs, total_fat, total_fiber, created_at]
contract_test_path: test/sync/nutrition_pull_removed_behavioral_test.dart
ist_handling: []
provider_invalidations: [dailyNutritionProvider, nutritionSummaryProvider, recentFoodLogsProvider, macroTargetsProvider, aiInsightProvider, foodLogProvider, "NutritionWriteService.onStateChanged (app.dart)"]
telemetry_op_types:
  success: [nutrition_pull_copies_removed]
  failure: [pull_cross_channel_logs, sync_nutrition_pull_copy_cleanup]
cross_account_guard: "true: the cleanup checks HiveUserSession.currentOwnerFullId == userId and !ownerChangedSince(userId) before the scan, before the delete and before the flag write."
forbidden_patterns_checked:
  - { pattern: "a meal row written under a key that is not nlog_ / saved_meal_ / meal_", absent: true }
  - { pattern: "a fourth non-comment line naming the dropped chat channel in lib/ (telegram_surface_removed_test allowedLines)", absent: true }
proposed_fix: |
  pullRecentCrossChannelLogs no longer runs the nutrition leg (configBox restore_nutrition_launch_pull runs it again: the old path kept verbatim, CLAUDE.md 4.6). Before the legs it awaits _cleanupNutritionPullCopies, which removes once per user (syncBox nutrition_phantom_clean_<userId>, written also when nothing matched) every row of the exact copy shape (isNutritionPullCopy: UUID key, Map with user_id + date + meal_type, no items, not a saved meal, source not cloud_restore), owner-checked, then invalidates the nutrition providers. It never throws (own try/catch), so the weight and measurement legs always run. Kill switch disable_nutrition_phantom_clean.
regression_test_planned: |
  test/sync/nutrition_pull_removed_behavioral_test.dart (10 tests, drives the real pull body through the test seam pullRecentCrossChannelLogsForUser against the stub server).
mutation_proof: |
  Rule 21, backup to the scratchpad / mutate / run / restore with cp, cmp-checked after every run (never git checkout: the fix was uncommitted). Each mutation was confirmed applied (cmp differs; M5 diff shown).
  M1 the nutrition leg runs unconditionally: 1 RED (the leg reads and writes the copy). M2 the `items` clause dropped from the rule: 2 RED. M3 the provider invalidation dropped: 1 RED. M4 the `source != cloud_restore` clause dropped: 2 RED. M6 the cleanup rethrows: 1 RED (the weight leg is skipped). M5 the owner checks: removing the first two of the three left the check right before the delete in place and the suite stayed GREEN (correct: that check alone protects the data); removing all three: 1 RED ("another account live"). Each single check is masked by the others (layered by design), stated rather than hidden.
  B-pass round (docs/reviews/oi348-device-walk-bpass.md, 3 findings, all fixed): the Hive-owner check now has its own test ("Hive boxes owned by another account"): dropping `currentOwnerFullId != userId ||` reddens 1 test (was 15/15 green). The provider re-read moved to `finally` after a started delete: forcing it off reddens 2 tests (the new partial-delete test and the removal test). Registry line ranges for `_fetchAllRows`, `_reportSyncFailure` (two entries) and `kNlogKeyShape`..`firstFreeLogKey` re-derived.
impact_analysis: |
  Only rows of the copy shape are deleted. Every legitimate meal writer keys nlog_ / saved_meal_ / meal_ (nutrition_write_service.dart, sync_nutrition.dart restore and saved-meal writers) and the push sends only nlog_ keys, so a copy was never in the cloud and deleting it loses nothing that the cloud does not hold. Behaviour change, stated: a copy that was a meal logged on ANOTHER device (no nlog_ twin here) showed once and correctly; it is removed too, so such a meal reaches a populated device only at its next full restore (sign-in, reinstall) until Landing 1a-ii (nutrition slot sync, same batch) adds a real cross-device pull. Item-less cloud rows from the dropped channel are not restored by _restoreNutritionLogs either (sync_nutrition.dart restore loop skips a slot with no items). Every account is a testing account (CLAUDE.md 1).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync_service.dart pullRecentCrossChannelLogs + seam; sync_nutrition.dart isNutritionPullCopy, _cleanupNutritionPullCopies; nutrition_write_service.dart invalidateAfterSync. flutter analyze lib/: no errors or warnings." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "Copies removed once per user; behavioural test asserts every look-alike row (nlog_, saved meal, UUID row with items, saved-meal UUID row, cloud_restore UUID row, skip index) is kept." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "information_schema 2026-11-22: nutrition_logs has no items or source column, so the copy never carries items." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Upendra's cloud rows 2026-11-22 held each meal once (breakfast 1033, apple 95)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The leg no longer reads nutrition_logs (test asserts zero requests to the table); the push and restore paths are untouched." }
recurrence: "Recurrence of the class 'restore writer keyed differently from production writer' (lib/core/services/CLAUDE.md pitfall row, APK Test #12.8; d4a7c9 coach rows keyed by a server value). This writer keyed meals by the cloud row id while the production writer keys nlog_<date>_<meal>_<hash>; the restore writer was fixed for the same reason in Test #12.8 but this pull was not."
related_bugs: [d4a7c9, c9f2a7, e4a8b1]
---

# b1d2a8 - nutrition-pull-copies-doubled

## What happened
`pullRecentCrossChannelLogs` was built for the chat channel dropped on 2026-11-04 (OI-476). Its nutrition leg ran at every launch and copied each cloud meal row of the last 24 h under the cloud row id, with totals and no items. On a device that had logged the meal itself, the real `nlog_` row and the copy were both counted by every whole-box reader, so the meal and the day total doubled; the copy's card took its name from the slot because it had no items. The code had not changed since March; earlier builds showed it only for meals logged within 24 h of a launch.

## The fix
The leg is off; a one-time, owner-checked removal deletes the copies already written; the old path stays behind `restore_nutrition_launch_pull`. A real cross-device meal sync (conditional push, tombstones, cursor pull) is Landing 1a-ii, `docs/plans/nutrition-slot-sync.md`, in the same batch.

## Residual, stated
Until 1a-ii lands, a meal logged on another device appears on a populated device only after a full restore there.
