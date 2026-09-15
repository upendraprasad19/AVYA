---
bug_id: a2c8e6
date: 2026-06-12
batch: audit-2026-06-10
status: fixed
blast_radius: platform
symptom: >
  Quarterly audit (L21 lens) finding F1, founder-authorized fix. The
  delete-account Edge Function (DPDP §17 erasure) cancels the user's Razorpay
  subscription BEFORE deleting the account (correct — protects the user from
  post-deletion charges). But EVERY failure of that cancel step — a
  subscription-lookup error, a Razorpay HTTP non-ok, or a fetch exception —
  returned `jsonError(502, "razorpay_cancel_failed")` and ABORTED the entire
  erasure before auth.users was deleted. A transient Razorpay API outage could
  therefore indefinitely BLOCK a legally-required DPDP §17 deletion. The b4e2a9
  diagnose itself flagged this as a "make non-fatal once recurring billing
  launches" follow-up.
concept: dpdp_erasure_must_not_block_on_external_dependency
sot_registry_entry: not_applicable
writers: >
  supabase/functions/delete-account/index.ts (the cancel step — now non-fatal,
  records razorpayStatus into account_deletion_log).
readers: >
  account_deletion_log.razorpay_cancel_status (the durable audit record an
  out-of-band process / manual audit reads to find failed cancellations).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function)
sync_methods: []
restore_methods: []
cloud_table: account_deletion_log
cloud_columns: "razorpay_cancel_status (text, no length limit — verified live; records no_active_sub | cancelled | lookup_failed | cancel_failed:<sub>:<status>,...)"
contract_test_path: test/contracts/delete_account_razorpay_cancel_nonfatal_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "razorpay-cancel block returning jsonError(502, razorpay_cancel_failed) — removed; the erasure now proceeds and the failure is recorded in razorpay_cancel_status."
  - "silently swallowing a failed cancel — NOT done: cancelFailures are recorded durably in account_deletion_log for out-of-band follow-up."
proposed_fix: >
  Make the Razorpay-cancel step best-effort/non-fatal: still cancel-first, but on
  a lookup error set razorpayStatus='lookup_failed'; on a cancel non-ok/exception
  push to a cancelFailures list + continue the loop; after the loop, if any
  failed, set razorpayStatus='cancel_failed:<sub>:<status>,...' (≤400 chars). The
  erasure PROCEEDS regardless, and account_deletion_log.razorpay_cancel_status
  (no FK, survives the auth delete) durably records the outcome so the
  subscription can be cancelled out-of-band — the user is NOT silently left
  subscribed.
regression_test_planned: >
  test/contracts/delete_account_razorpay_cancel_nonfatal_test.dart — scoped
  source-grep (EF runs in Deno): the RAZORPAY CANCEL block no longer contains
  return jsonError(502, "razorpay_cancel_failed"); it tracks cancelFailures +
  records cancel_failed; cancel-first preserved; account_deletion_log still
  records razorpay_cancel_status.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "delete-account/index.ts cancel step made non-fatal; delete_account_razorpay_cancel_nonfatal_test 3/3" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "account_deletion_log.razorpay_cancel_status is text (no length limit) — the longer cancel_failed status fits; the audit insert won't fail" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: deferred, evidence: "CODE fixed + committed this batch; the LIVE delete-account EF deploy is HELD for the founder's separate explicit go (§4.3 live-apply gate). The closure ledger marks deploy: held." }
impact_analysis: >
  Platform blast radius (DPDP-compliance Edge Function). Pre-fix, a transient
  external dependency (Razorpay API) could indefinitely block a legally-required
  §17 erasure — a real compliance exposure (low-probability with one-time
  payments today, but real). The fix removes the block while preserving the
  cancel-first protection AND the durable record of any failed cancellation (so a
  user is never silently left subscribed). Founder authorized fix-now over the
  prior b4e2a9 upstream_blocked deferral. The live EF deploy is HELD for the
  founder's separate go per §4.3; until deployed, the running EF retains the old
  fatal behavior. related: b4e2a9 (the prior delete-account DPDP P0 + the
  documented follow-up this closes).
---

# delete-account Razorpay-cancel fatal → can block DPDP §17 erasure (a2c8e6)

## What happened
The delete-account EF cancels the Razorpay subscription before deleting the
account. Every failure of that step (lookup error / HTTP non-ok / exception)
returned `502 razorpay_cancel_failed` and aborted the erasure — so a transient
Razorpay outage could indefinitely block a legally-required DPDP §17 deletion.

## Root cause
"Cancel must succeed or abort" — a deliberate guard against post-deletion charges
that over-indexed on the billing risk and under-weighted the legal erasure right.

## Fix
Non-fatal cancel: still cancel-first, but a failure is recorded durably in
`account_deletion_log.razorpay_cancel_status` (`cancel_failed:<sub>:<status>`) for
out-of-band follow-up, and the erasure proceeds. The user is not silently left
subscribed.

## Verification
- `test/contracts/delete_account_razorpay_cancel_nonfatal_test.dart` 3/3.
- `account_deletion_log.razorpay_cancel_status` is `text` (live-verified) — the
  longer status fits.
- **Live deploy HELD** for the founder's separate go (§4.3).

## See also
- supabase/functions/delete-account/index.ts (RAZORPAY CANCEL block)
- docs/diagnoses/...-b4e2a9... (the prior delete-account DPDP work + this follow-up)
- docs/architecture/payment.md (DPDP delete-account flow)
