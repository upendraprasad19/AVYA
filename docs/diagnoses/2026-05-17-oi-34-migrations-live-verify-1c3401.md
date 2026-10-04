---
bug_id: 1c3401
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  Existing `check_migrations_applied.dart` (Gate 14) compared local
  migration filenames against `backups/applied_migrations.json` —
  a manually maintained snapshot. If the snapshot is stale or someone
  forgets to update it, the gate green-checks while migrations are
  actually unapplied. Script header carried a known-issue comment.
concept: migration_live_verify_gate
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: scripts/check_migrations_live.dart, method: Management API query + diff, line: 1 }
readers:
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-34 group, line: 73 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: supabase_migrations.schema_migrations
cloud_columns: [version, name]
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — local build gate"
forbidden_patterns_checked:
  - { pattern: "snapshot-only verify with no live API alternative", absent: true }
proposed_fix: |
  New `scripts/check_migrations_live.dart` hits Supabase Management API
  `/v1/projects/<id>/database/migrations` with the PAT from
  `supabase/.supabase/supabase access token.txt`. Compares local
  `supabase/migrations/*.sql` numeric prefixes against returned version
  list. Skips cleanly (exit 0) on missing token or network failure so
  Gate 14 (offline snapshot) remains the safety net. Known limitation:
  prefix-heuristic matcher; refinement deferred since false-positive
  failures are conservative.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug 1c3401 — check_migrations_live.dart shipped

closes-oi: OI-34

Gate-strictness lens (L24). Companion to Gate 14 snapshot. Wire into `/build-apk` for release-mode strict verification.
