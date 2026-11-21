---
reviewed_at: 2026-06-08T07:55:00+05:30
staged_against: 8bbe903d448c
blast_radius: catastrophic
reviewer: hermes-e-pass + author-verification
lens_set: [L21, L36, L1, L28, L22, L23, L39]
findings_count: 1
verdict: accepted
---

# Code Review — 8bbe903d448c (Hermes E-pass follow-ups)

This diff IS the remediation of the Hermes E-pass over the whole branch
(`docs/audit/2026-06-08-hermes-psych-audit-batch.md`) — the deepest review run on this
batch (7 parallel fresh-context Opus lenses). The E-pass served as the review for this
change; findings are fixed + verified below.

## P0 — verify-payment duplicate `const existingSub` (L21 + L36) — FIXED + VERIFIED
- The Batch-6 F31/F33 refactor's idempotency pre-SELECT bound `existingSub`, colliding
  with the pre-existing active-sub `const existingSub` (~line 279) in the same handler →
  module-load SyntaxError → v14 wouldn't boot. Diagnose `f5d8c3`.
- **Fix:** renamed to `paymentSubRow` (binding only; the F31/F33 redeem-once + canonical
  expiry logic is byte-unchanged). Line 279's `existingSub` untouched.
- **Verified live:** v15 redeployed; an anon-Bearer POST returns the MODULE's own 401
  ("Invalid or expired token") twice — proving the module loads (not a 503 BOOT_ERROR).
  The unauth deploy smoke is gateway-masked for verify_jwt=true, so this anon-Bearer probe
  is the real boot check.
- **Regression:** `audit_2026_06_07_batch6_server_test.dart` asserts <=1 `existingSub`
  declaration + the `paymentSubRow` binding.

## Low-severity follow-ups (all fixed + tested)
- **L1:** added the `'recomp'`→`'recompose'` bridge assertion to
  `recompose_goal_targets_test.dart` (the one un-pinned F19-reintroduction surface). Test green.
- **L28:** `switchGoal.ts` enum + description now include `recompose` (the AI could not switch
  a user to the batch's headline goal). Source change — ships with the next ai-proxy deploy.
- **L28:** `tool_dispatcher._executeSwitchGoal` now rejects any token `FitnessGoals` doesn't
  know before writing `primary_goal` (defense-in-depth on the F19 class). analyze clean.

## Clean / accepted (from the E-pass)
- L22: verify-payment insert column set == old upsert (nothing dropped); the
  `razorpay_order_id ?? null` smell is pre-existing + unreachable. L23: all service-role
  paths gated. L39: F37/F38/F39 round-trips clean (the branch-staleness vs main's
  additive-restore guards is resolved by the pre-merge resync, not a code defect).

## Verdict: accepted
The P0 is fixed + live-verified; all real findings fixed in-batch. The E-pass earned its
keep — it caught a live-broken payment function that 4 B-passes + the author missed.
