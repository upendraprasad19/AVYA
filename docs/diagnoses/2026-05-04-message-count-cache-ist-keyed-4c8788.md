---
bug_id: 4c8788
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: AI coach message count was recomputed from Supabase on every render, causing unnecessary round-trips; cache key was not IST-aware, causing stale counts across midnight.
concept: coach_interactions
sot_registry_entry: coach_interactions
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: AiCoachProvider, line: 1 }
readers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: messageLimitProvider, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [created_at, channel]
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: cacheKey, line: 1 }
provider_invalidations: [messageLimitProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Cache message count with IST date key; invalidate cache on new message send or day rollover.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 4c8788e1b01cf356ec8152ef3a9dd564a8064278
Subject: perf(ai_coach): cache message count, IST keyed (Test #11 M5)
Files changed: lib/features/ai_coach/providers/ai_coach_provider.dart, lib/features/auth/screens/splash_screen.dart, test/ai_coach/message_limit_cache_test.dart
