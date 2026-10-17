---
bug_id: d9d77c
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Captain voice prompts were duplicated across proactive trigger Edge Functions instead of sharing a single source, risking voice drift between triggers.
concept: coaching_notes
sot_registry_entry: coaching_notes
writers:
  - { file: supabase/functions/_shared/captain_manual.ts, method_or_widget: captainPrompt, line: 1 }
readers:
  - { file: supabase/functions/morning-alert/index.ts, method_or_widget: handler, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Promote captain_manual.ts to shared module; all proactive triggers import captainPrompt(channel) with English fallback.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: d9d77c4364257888e7918e739a2b8290c5db87d9
Subject: feat(G1): promote CAPTAIN_MANUAL to shared module; all proactive triggers now Captain-voiced
Files changed: supabase/functions/_shared/captain_manual.ts, supabase/functions/morning-alert/index.ts, supabase/functions/plateau-alert/index.ts
