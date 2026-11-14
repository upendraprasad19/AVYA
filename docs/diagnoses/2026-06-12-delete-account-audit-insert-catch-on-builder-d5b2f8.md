---
bug_id: d5b2f8
date: 2026-06-12
batch: e2e-obs-fixes
status: fixed
blast_radius: platform
symptom: >
  The SECOND never-run delete-account bug, revealed the instant the e8a1c3 auth
  fix let the erasure path execute for the first time. With a VALID token, the EF
  now passed auth, ran the full erasure, and the auth.users cascade delete
  SUCCEEDED (test1 def7bb05 + all child rows gone) — but the EF then returned
  500 "internal_error" (req 597b6c3a) and the account_deletion_log audit row was
  never written (del_log=0). Cause: the audit insert chained `.catch()` on a
  PostgREST builder, which is a thenable with NO `.catch` method, so `.catch`
  evaluated to undefined and `undefined(fn)` threw a TypeError → the outer catch
  → 500 (after the irreversible delete) AND the insert never ran.
concept: postgrest_builder_has_no_catch_method
sot_registry_entry: not_applicable
contract_test_path: test/contracts/delete_account_auth_pattern_test.dart
writers: >
  supabase/functions/delete-account/index.ts (the AUDIT LOG step — now
  await + { error } check inside a try/catch, never rethrows).
readers: >
  account_deletion_log (the durable DPDP audit record; razorpay_cancel_status the
  ORPHAN_BILLING out-of-band reader).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function)
sync_methods: []
restore_methods: []
cloud_table: account_deletion_log
cloud_columns: "deleted_user_id, deleted_at, request_id, razorpay_cancel_status, storage_purge_status"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "admin.from('account_deletion_log').insert({...}).catch(...) — a PostgREST builder has no .catch() method → TypeError → 500. REMOVED; replaced with await + { error } check inside try/catch."
proposed_fix: >
  Replace `.insert({...}).catch(fn)` with the supabase pattern:
  `const { error: auditErr } = await admin.from('account_deletion_log').insert({...}); if (auditErr) throw auditErr;`
  all wrapped in a try/catch whose catch preserves the a2c8e6 ORPHAN_BILLING
  last-resort logging. The catch NEVER rethrows — the account is already deleted
  (point of no return), so an audit-insert failure must not 500 the response.
regression_test_planned: >
  test/contracts/delete_account_auth_pattern_test.dart (d5b2f8 group) — source-grep
  with comment-stripping: the account_deletion_log insert uses `const { error:
  auditErr } = await ...` and does NOT chain `.catch(` on the builder.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "audit insert → await + error-check in try/catch; delete_account_auth_pattern_test d5b2f8 group green" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "delete-account redeployed (v6); boot-verified. Live re-test of a full deletion not possible (test1 already erased by the v5 run before this throw) — covered by the regression test + the v5 evidence that auth.users delete + cascade succeeded." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "post-v5-500: test1 def7bb05 is gone from auth.users/public.users/all child tables (cascade succeeded); only account_deletion_log was not written — the symptom this fixes." }
impact_analysis: >
  Platform/DPDP blast radius. The erasure itself worked (account + data deleted),
  but the EF reported failure (500) and skipped its DPDP audit-trail row — so a
  real user's deletion would look failed (client shows a generic error / may
  retry) and the compliance audit record would be missing. Both delete-account
  never-run bugs (e8a1c3 auth + d5b2f8 audit) were masked because the auth gate
  401'd every request before the erasure could run. related: e8a1c3 (the auth fix
  that revealed this), a2c8e6 (the ORPHAN_BILLING last-resort log, preserved).
---

# delete-account audit insert `.catch()` on a PostgREST builder → 500 after a successful delete (d5b2f8)

## What happened
Once e8a1c3 fixed the auth gate, the erasure ran for the first time. The auth.users
cascade delete **succeeded** (account + all data erased), but the EF returned
**500** and never wrote `account_deletion_log` (del_log=0).

## Root cause
`admin.from("account_deletion_log").insert({...}).catch(fn)` — a PostgREST builder
is a thenable with **no `.catch` method**. `.catch` is `undefined`, so `undefined(fn)`
throws a `TypeError` (synchronously, so the insert never even runs) → the outer
catch → 500. It had never fired because the auth gate (e8a1c3) 401'd every request
before this line could run.

## Fix
```ts
try {
  const { error: auditErr } = await admin.from("account_deletion_log").insert({...});
  if (auditErr) throw auditErr;
} catch (e) { /* ORPHAN_BILLING last-resort log; NEVER rethrow */ }
```

## Verification
- `test/contracts/delete_account_auth_pattern_test.dart` (d5b2f8 group).
- delete-account redeployed v6 + boot-verified. (A fresh full-deletion live re-test
  isn't possible — test1 was already erased by the v5 run; the v5 evidence proves
  the auth.users delete + cascade succeed, and the regression test pins the pattern.)

## See also
- supabase/functions/delete-account/index.ts (AUDIT LOG step)
- docs/diagnoses/...-e8a1c3... (the auth fix that revealed this)
