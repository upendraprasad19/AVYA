---
bug_id: b3f0d9
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 6, server Edge-Function / cron)
status: fixed
blast_radius: catastrophic
symptom: >
  Eight server-side Edge-Function / cron defects from the 2026-06-07 audit. F44
  (SECURITY): proactive-coach-promotion ran verify_jwt=false with NO auth gate, so
  an unauthenticated POST drove Gemini cost + OneSignal push + ai_coach_interactions
  writes to ANY user_id. F31: verify-payment redeemed a promo unconditionally after
  the insert block, so on a 23505 webhook race (the webhook already created the row
  AND redeemed) it double-redeemed — over-counting used_count + duplicating the
  promo_code_uses audit row. F33: verify-payment returned verified:true on a
  non-23505 insert failure WITHOUT writing the row, so PRO was granted optimistically
  then vanished on cold start. F32: razorpay-webhook measured replay age from the
  payment entity's created_at, so a slowly-approved UPI-collect capture (created
  minutes before the webhook fired) was rejected FOREVER and PRO never unlocked. F43:
  pr-detection scanned by created_at (row sync time) not completed_at, so an
  offline-synced PR fired a stale push days late. F45: i-see-you-callout scanned ALL
  users unconditionally with sequential per-user queries — unbounded cost. F46:
  streak-guardian docstring drifted from the live schedule. F47: CRON_REGISTRY named
  a fictional proactive-triggers job/function.
concept: server_edge_function_and_cron_hardening
sot_registry_entry: "subscriptions → verify-payment + razorpay-webhook (CLAUDE.md migrations table); cron auth gate → _shared/cron_auth.ts isAuthorizedCronCall (every cron + trigger-dispatched verify_jwt=false fn)"
writers:
  - "{ file: supabase/functions/verify-payment/index.ts, line: 484 } — F31/F33 redeem-once flag + honest insert-failure"
  - "{ file: supabase/functions/razorpay-webhook/index.ts, line: 303 } — F32 replay age from event time"
  - "{ file: supabase/functions/proactive-coach-promotion/index.ts, line: 88 } — F44 isAuthorizedCronCall gate"
readers:
  - "{ file: supabase/functions/pr-detection/index.ts, line: 77 } — F43 recency by completed_at"
  - "{ file: supabase/functions/i-see-you-callout/index.ts, line: 100 } — F45 active-user + paginated scan"
  - "{ file: supabase/functions/streak-guardian/index.ts, line: 2 } — F46 docstring matches live 20:00 IST"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: subscriptions
cloud_columns: "subscriptions(razorpay_payment_id, status, end_date) — F31/F33 pre-SELECT + insert; workout_log_exercises(completed_at) — F43"
contract_test_path: test/contracts/audit_2026_06_07_batch6_server_test.dart
ist_handling: "F46 — streak-guardian runs 14:30 UTC = 20:00 IST (live jobid 20 = 30 14 * * *); docstring + CRON_REGISTRY corrected to match"
provider_invalidations: n/a
telemetry_op_types: "F43 pr-detection (proactive push); F44 proactive-coach-promotion now rejects unauthorized BEFORE any telemetry/Gemini/push"
cross_account_guard: "F44 — the auth gate prevents an attacker driving writes to ANY user_id; F31 pre-SELECT keys on razorpay_payment_id whose notes.user_id was already asserted == JWT user (OI-29)"
forbidden_patterns_checked: >
  verify-payment carries weInsertedTheRow + the razorpay_payment_id pre-SELECT and
  no longer returns the verified:true-without-a-row path; razorpay-webhook keys
  replay age off payload.created_at, not paymentEntity.created_at; pr-detection has
  no created_at recency ref; proactive-coach-promotion calls isAuthorizedCronCall;
  i-see-you-callout uses last_active_at + .range + PAGE_SIZE; streak-guardian says
  20:00 IST not 23:50. cron_auth_adoption_test now also covers the trigger-dispatched
  proactive-coach-promotion (the gate gap that let F44 ship).
proposed_fix: >
  F44: add isAuthorizedCronCall(req) (the canonical _shared/cron_auth.ts helper the
  sibling crons use) at the top of serve, before any work; the live dispatch
  (migration 078 trigger sends Bearer <service_role_jwt>) still authenticates. Also
  add proactive-coach-promotion to cron_auth_adoption_test (trigger-dispatched list)
  so the gate is its regression guard. F31: idempotency pre-SELECT by
  razorpay_payment_id + weInsertedTheRow flag gating redeemPromo (redeem only if WE
  created the row). F33: a non-23505 insert failure now returns verified:false + 500.
  F32: replay age from payload.created_at (event time). F43: filter/order by
  completed_at. F45: scope to users active within 28d (last_active_at) + paginate
  (PAGE_SIZE 1000, .range). F46/F47: reconcile the docstring + CRON_REGISTRY +
  deploy smoke-map to live cron state (20:00 IST; the 5 real proactive_* jobs, not a
  fictional proactive-triggers).
regression_test_planned: test/contracts/audit_2026_06_07_batch6_server_test.dart (8 tests GREEN) + cron_auth_adoption_test.dart (now covers proactive-coach-promotion)
touched_layers_checked:
  - "{ layer: edge_function_code, status: fixed_in_this_batch, evidence: 5 functions edited + 8 contract tests green; verify_jwt preserved per live config (verify-payment=true, others=false). The live DEPLOY is byte-identical + smoke-ready but held for the founder's explicit per-action go — the live-apply classifier (CLAUDE.md §4.3) is correctly blocking it (not worked around); deployed versions recorded here on the authorized apply }"
  - "{ layer: cron, status: verified, evidence: live cron.job query (2026-06-07) — 21 active jobs; no proactive-triggers job exists (F47); streak-guardian-daily jobid 20 = 30 14 = 20:00 IST (F46) }"
  - "{ layer: client_server_contract, status: fixed_in_this_batch, evidence: F31 redeem-once mirrors the webhook H-19 idempotency; F32 webhook now unlocks PRO for slow UPI captures }"
impact_analysis: >
  F44 is a real unauthenticated-cost + cross-user-write hole (security P1). F31/F33
  are payment-integrity bugs (promo over-redemption + phantom PRO). F32 silently
  blocked PRO for every slow UPI-collect payer. F43 fired stale PR pushes. The
  payment functions are catastrophic blast-radius, so the deploys themselves are held
  for an explicit per-action authorization even though the founder pre-approved the
  batch — the classifier block is correct (§4.3) and was not worked around.
closes-diagnose: b3f0d9
---

# Server Edge-Function / cron hardening (F31, F32, F33, F43, F44, F45, F46, F47)

The server half of the 2026-06-07 audit. Two payment functions, one security gate,
two cron-cost/correctness fixes, and a live-state doc reconcile.

## Fixes
- **F44 (SECURITY)** — `proactive-coach-promotion` now gates on
  `isAuthorizedCronCall(req)` before any Gemini/push/DB work. The migration-078
  trigger sends `Bearer <service_role_jwt>`, so the live dispatch keeps working;
  anonymous POSTs get 401. The **root cause** — `cron_auth_adoption_test` only
  covered pg_cron functions, not trigger-dispatched ones — is closed by adding a
  `_triggerDispatchedFunctions` list to that gate.
- **F31 / F33** — `verify-payment`: idempotency pre-SELECT by `razorpay_payment_id`
  + a `weInsertedTheRow` flag. The promo is redeemed **only if we created the row**
  (no double-redeem on a webhook race); a non-23505 insert failure returns
  `verified:false` + 500 (no phantom PRO).
- **F32** — `razorpay-webhook` replay age now keys off `payload.created_at` (event
  time), not the payment entity's creation time, so a slow UPI-collect capture is no
  longer rejected forever.
- **F43** — `pr-detection` filters/orders by `completed_at` (real workout time).
- **F45** — `i-see-you-callout` scopes to users active within 28 days + paginates.
- **F46 / F47** — reconciled to **live cron state** (verified via `cron.job` query):
  streak-guardian runs **20:00 IST** (not the stale registry's 23:50 — the docstring
  + CRON_REGISTRY are corrected); the fictional `proactive-triggers` registry row is
  replaced by the 5 real `proactive_*` jobs (migration 031), and the deploy smoke-map
  ghost is fixed.

## Deploy status
Founder pre-authorized the deploys; the live-apply classifier (§4.3) correctly
requires an explicit per-action go, which was **not** worked around. Deploy targets
(byte-identical, `verify_jwt` preserved): `verify-payment` (true, v13→),
`razorpay-webhook` (false, v18→), `pr-detection` (false, v6→),
`proactive-coach-promotion` (false, v3→), `i-see-you-callout` (false, v4→).
`streak-guardian` is a docstring-only change (no functional redeploy needed).
Versions get recorded here on the authorized deploy.

## Guard
`test/contracts/audit_2026_06_07_batch6_server_test.dart` (8 tests) +
`cron_auth_adoption_test.dart` (now covers `proactive-coach-promotion`).
