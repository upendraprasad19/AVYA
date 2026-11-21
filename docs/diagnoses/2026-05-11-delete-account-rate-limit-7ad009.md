---
bug_id: 7ad009
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: delete-account Edge Function had no rate limit on the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could repeatedly POST attempts; each fires Razorpay + DB queries before the 400 reject — DoS vector at scale.
concept: delete_account_rate_limit
sot_registry_entry: delete_account_rate_limit
writers:
  - { file: supabase/functions/delete-account/index.ts, method_or_widget: rate_limit_gate, line: 1 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [channel, user_id, created_at]
contract_test_path: "n/a — Edge Function rate-limit verified via curl"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["delete_account_no_rate_limit"]
proposed_fix: delete-account v2 adds rate limit - 5 attempts per user per hour counted via ai_coach_interactions rows with channel=delete_account_attempt. Mirrors verify-payment pattern. Fail-open on rate-limit query error (user is exercising a right not making a payment). Returns 429 with Retry-After header when exceeded.
regression_test_planned: []
---
# Audit Hermes-R2 #9: delete-account rate limit

## Bug

`delete-account/index.ts` did per-call Razorpay subscription lookup + auth.getUser BEFORE the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could fire 1000s of POST attempts. Each attempt hits external services before being rejected.

## Fix

v2 deployed 2026-05-11 with rate-limit gate inserted after JWT auth, before confirmation-token check:
- 5 attempts per user per 60-min window
- Counted via `ai_coach_interactions` rows with `channel='delete_account_attempt'`
- Fail-open on counter-query error (DPDP right to erase — don't block)
- Each attempt inserts a placeholder row (fire-and-forget)
- 429 response includes `Retry-After: 3600` header

## Related

- CLAUDE.md §16 (verify-payment rate-limit pattern — mirrored)
- 7ad0c5 (promote-community-item admin gate — same family of Edge Function gates)
