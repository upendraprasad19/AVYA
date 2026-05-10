---
bug_id: fe579a
date: 2026-05-06
batch: APK Test #12.5
status: shipped
symptom: ai_coach_repository called istDateStr(istNow()) causing a double IST shift — plan summaries showed wrong date and eta_next_promotion dates were off by one day.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: AiCoachRepository.buildAiContext, line: 1 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: AiCoachRepository, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: _getYesterdayWorkout, line: 1 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Replace istDateStr(istNow().subtract(...)) with istDateStr(DateTime.now().subtract(...)) — istDateStr handles the IST shift once internally; never pass istNow() result to istDateStr.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: fe579a7a8090ec86616c70d8e34276922324f94e
Subject: fix: IST double-shift in ai_coach_repository (Test #12.5 follow-up)
Files changed: lib/features/ai_coach/providers/ai_coach_provider.dart
