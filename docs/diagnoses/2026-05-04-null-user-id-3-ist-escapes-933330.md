---
bug_id: 933330
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Post-account-deletion null user_id in community rows caused promote-community-item to crash; three additional IST date escape sites wrote UTC dates to Hive.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: ConversationalLogHandler, line: 1 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: relogSavedMeal, line: 1 }
hive_key_prefix: "nlog_"
hive_key_formula: "null"
sync_methods: [syncNutritionData]
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: _logFood, line: 1 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Guard promote-community-item with if(source.user_id) check; fix 3 IST escape sites in conversational_log_handler, nutrition_provider.relogSavedMeal, search_mode_body._relogFromHistory.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 9333304f9b7ce1a2f3db96c6d632c64ed1020ad0
Subject: fix: post-review P1 cleanup — null user_id + 3 IST escapes (Test #11 final pass)
Files changed: lib/features/ai_coach/services/conversational_log_handler.dart, lib/features/nutrition/providers/nutrition_provider.dart, lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart, supabase/functions/promote-community-item/index.ts
