---
bug_id: a2d0e1
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  delete-account Edge Function only listed top-level entries under
  `userId/` for each Storage bucket. Nested paths (`userId/2026/photo.jpg`,
  `userId/subfolder/...`) survived account deletion. DPDP §17 requires
  erasure of all user-tagged objects, nested or otherwise.
concept: delete_account_storage_purge_recursive
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/delete-account/index.ts, method: listAllObjectsRecursive helper, line: 327 }
  - { file: supabase/functions/delete-account/index.ts, method: purge loop calls helper, line: 358 }
readers:
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-32 group (2 cases), line: 12 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: storage.objects
cloud_columns: [bucket_id, name]
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — delete-account is service-role, scope is the single user being deleted"
forbidden_patterns_checked:
  - { pattern: ".list(userId) without recursive helper", absent: true }
proposed_fix: |
  Added `listAllObjectsRecursive(bucket, prefix)` helper that does DFS
  via repeated `.list(current, { limit: 1000, offset })` calls. Folder
  entries (id === null) are pushed onto a stack; file entries are
  collected. Pagination handles users with > 1000 photos. The purge
  loop calls the helper then `.remove()` in 1000-chunk batches (REST
  batch limit). Per-chunk errors accumulate without breaking the loop.

  delete-account v2 → v3 deployed.

  Why missed: lens L23 (service-role authz defense-in-depth) didn't
  exist; OI-12 RLS audit was table-level only.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug a2d0e1 — delete-account Storage purge non-recursive

closes-oi: OI-32

The Supabase Storage SDK has no `recursive: true` option on `.list()`. DPDP §17 requires erasure of all user-tagged objects; the prior `.list(userId)` call returned only top-level entries (subdirectory NAMES, not subdirectory CONTENTS). Added a `listAllObjectsRecursive` DFS helper + chunked `.remove()`.

Verification: 1 contract test asserts the helper exists; 1 asserts the purge loop calls it (and forbids the flat-list regression in non-comment code). delete-account v3 deployed.
