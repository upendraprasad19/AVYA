---
bug_id: c8f229
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase A (P0 payment blockers)
status: shipped
symptom: |
  verify-payment ownership check at `if (notesUserId && notesUserId
  !== userId) { return 403; }` was fail-open when `payment.notes.user_id`
  was absent. An attacker who learns a captured Razorpay payment_id
  without notes (e.g. legacy payment, manual capture via Razorpay
  dashboard) could claim entitlement under their own JWT — call
  verify-payment with the payment_id, no notes.user_id present, check
  passes, subscription row created with attacker's user_id.

  Severity is tempered (not eliminated) by: (a) plan is derived from
  amount not from client, (b) row owner is the JWT-authenticated userId
  not arbitrary, (c) payment_ids are UUID-shaped + not enumerable.
  Real attack requires knowledge of a specific captured payment_id
  that lacks notes.
concept: verify_payment_notes_user_id_guard
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/verify-payment/index.ts, method: notes.user_id absent guard (400), line: 361 }
  - { file: supabase/functions/verify-payment/index.ts, method: notes.user_id mismatch guard (403), line: 373 }
readers:
  - { file: test/contracts/verify_payment_notes_user_id_required_test.dart, method_or_widget: guard-order contract test, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns:
  - user_id
  - razorpay_payment_id
contract_test_path: test/contracts/verify_payment_notes_user_id_required_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "userId from JWT must equal payment.notes.user_id; mismatch OR absence rejects"
forbidden_patterns_checked:
  - { pattern: "legacy fail-open if (notesUserId && notesUserId !== userId) in code (not comments)", absent: true }
  - { pattern: "missing 400 guard when notes.user_id absent", absent: true }
proposed_fix: |
  Replace the single check `if (notesUserId && notesUserId !== userId)`
  with two explicit guards:

  1. `if (!notesUserId) { return 400 "Missing user_id in payment notes"; }`
  2. `if (notesUserId !== userId) { return 403 "Payment does not belong to this user"; }`

  razorpay-webhook already has the equivalent guard at lines 406-415
  ("Missing user_id in payment notes" + 400) — verify-payment now
  mirrors that pattern.

  Considered + rejected: also requiring notesUserId to be a UUID
  shape. Already enforced for `userId` at the function entry (lines
  ~418-429 region). If notes.user_id is a non-UUID string, it'll
  trivially mismatch the JWT-extracted UUID userId and hit the 403
  guard. Adding a third guard adds noise without new coverage.

  Why missed by today's audit: lens L23 (service-role authz
  defense-in-depth) did not exist. OI-12 RLS audit was table-level
  only — verified policies on tables but didn't audit service-role
  bypass paths in Edge Function code.
regression_test_planned:
  - test/contracts/verify_payment_notes_user_id_required_test.dart
---

# Bug c8f229 — verify-payment notes.user_id fail-open

closes-oi: OI-29

## Root cause

The `&&` short-circuit in `if (notesUserId && notesUserId !== userId)`
means: if `notesUserId` is undefined/null/empty, the conditional
evaluates to false and the rejection branch is skipped. The function
then proceeds to derive the plan from the amount and write a
subscription row owned by the JWT-extracted userId.

Original intent: "reject when notes.user_id differs from authenticated
user". Actual behavior: "reject when notes.user_id is present AND
differs". When notes is absent (legacy payment, manual capture in
Razorpay dashboard, etc.), the function proceeds.

## Attack model

1. Attacker knows a captured Razorpay payment_id without notes.
   Sources: legacy payments before notes were added; manual captures
   via Razorpay dashboard (no notes); payments fired via API by
   third-party integrations that don't set notes.
2. Attacker calls verify-payment with that payment_id + their own JWT.
3. verify-payment validates: `notesUserId = undefined` → first guard
   skipped → derive plan from amount → insert subscription row with
   attacker's userId.
4. Attacker now has PRO entitlement for a payment they didn't make.

Mitigations that limit blast radius (don't eliminate):

- Plan is derived from amount, so attacker gets whatever plan the
  payment paid for (not arbitrary).
- Row owner is the JWT-extracted userId (attacker's own account), so
  the original payer doesn't lose their subscription, but is
  duplicated.
- Razorpay payment_ids are 18+ char UUID-shaped strings — not
  enumerable.
- Most production payments DO have notes (CLAUDE.md §16 rule: client
  always sets `notes.user_id` when opening checkout).

But payment_ids leak in: webhook event logs, Razorpay dashboard
exports, support emails, Slack channels, error logs. The threat
surface is small but real.

## Fix

Two-step guard pattern matching razorpay-webhook:

```typescript
const notesUserId = payment.notes?.user_id;
if (!notesUserId) {
  return new Response(
    JSON.stringify({ verified: false, error: "Missing user_id in payment notes" }),
    { status: 400, ... },
  );
}
if (notesUserId !== userId) {
  return new Response(
    JSON.stringify({ verified: false, error: "Payment does not belong to this user" }),
    { status: 403, ... },
  );
}
```

## Behavioral change

Pre-fix: payments without notes silently succeeded.

Post-fix: payments without notes get a clear 400 "Missing user_id in
payment notes". Client maps this error message via
`AiService._extractError` to a user-actionable message. Legacy
payments need to be processed via admin/manual recovery path (not via
client polling).

## Why I'm not adding a "legacy payment" admin override

That would re-introduce the fail-open hole. Admin recovery for legacy
payments belongs in a separate admin-only Edge Function that takes a
service-role JWT, not the user-facing verify-payment endpoint.

## Verification

```
$ flutter test test/contracts/verify_payment_notes_user_id_required_test.dart
All tests passed! (3 cases)
```

Test 1 pins guard order (400 before 403). Test 2 forbids the legacy
`if (notesUserId && notesUserId !== userId)` pattern in CODE (not
comments — the OI-29 fix quotes the old pattern in a comment for
historical context). Test 3 pins the error message string so
client-side error mapping stays in sync.

## Related

- CLAUDE.md §16 — Razorpay payment flow + payment security rules
- `feedback_audit_methodology_lenses.md` — L23 service-role authz defense-in-depth (NEW)
- `docs/audit/LENS_REGISTRY.md` — canonical lens registry
- razorpay-webhook lines 406-415 — the canonical pattern this fix mirrors
