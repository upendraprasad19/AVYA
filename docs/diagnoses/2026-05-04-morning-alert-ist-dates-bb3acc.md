---
bug_id: bb3acc
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Morning alert Edge Function computed day-of-week and date strings in UTC instead of IST, sending wrong day greetings after 18:30 IST.
concept: coach_interactions
sot_registry_entry: coach_interactions
writers:
  - { file: supabase/functions/morning-alert/index.ts, method_or_widget: handler, line: 1 }
readers:
  - { file: supabase/functions/_shared/ist_date.ts, method_or_widget: istDateStr, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [created_at]
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: supabase/functions/_shared/ist_date.ts, method_or_widget: istDateStr, line: 1 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Create _shared/ist_date.ts helper; replace UTC date logic in morning-alert with IST-aware date strings for day-of-week and date display.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: bb3acc2d27aa0c330abe3238901099629a957369
Subject: fix(edge): morning-alert IST day-of-week + dates (Test #11 B3)
Files changed: supabase/functions/_shared/ist_date.ts (new), supabase/functions/morning-alert/index.ts
