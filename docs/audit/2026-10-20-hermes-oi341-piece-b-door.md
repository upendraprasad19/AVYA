---
hermes_pass_id: 2026-10-20-hermes-oi341-piece-b-door
ran_at: 2026-10-20T13:30:00+05:30
batch_scope: branch oi341-piece-b-door (from main efb20c4c), staged tree after the B-pass fixes; whole-file reads of supabase/functions/verify-payment/index.ts, supabase/functions/razorpay-webhook/index.ts, _shared/subscription_stacking.ts, _shared/payment_alert.ts and supabase/migrations/161_record_paid_subscription.sql
lens_set: [L1, L2, L14, L21, L22, L23, L29, L35, L40]
agents_dispatched: 4
model_deviation: "Sonnet, one wave of 4, not the skill's Opus default: the founder's standing rule (2026-09-26, 2026-10-07) overrides it."
findings_total: 8
findings_by_severity: { P0: 0, P1: 0, P2: 0, P3: 8, false_alarm: 0 }
verdict: accepted
---

# Hermes E-pass: OI-341 Piece B1 (the serialised stacking writer and the payment alert, dark)

## Summary

- 0 P0, 0 P1, 0 P2, 8 P3 records (6 distinct: the failure-path latency was raised by seats 1 and 2).
- Ship-blockers: none.
- Every finding is terminal in `docs/audit/oi341-piece-b-door.closure.yaml` (rows `H-S1-1`, `H-S2-1`, `H-S3-1`, `H-S3-2`, `H-S4-1`, `H-S4-2`).
- The pass ran AFTER the B-pass fixes (BP-A1..A4, BP-B1..B3), on the post-fix staged tree.

Seats: 1 = L1 + L29; 2 = L21 + L22; 3 = L23 + L40; 4 = L2 + L35 + L14. Every seat was read-only (file reads,
read-only git, grep), with no database statement, no network tool and no script run.

## Findings by lens

### L1 - writer/reader drift (seat 1)
Clean. Readers of `end_date` / `start_date` (`_shared/subscription.ts`, `grant_referral_days` in 159, the referral job's
`start_date`-as-payment-time read, the client poll `razorpay_service.dart:748-783`) keep their meaning on both paths; the
webhook's `alreadyProcessed = !rec.inserted` and verify-payment's `weInsertedTheRow = rec.inserted` mirror the OFF 23505 arms.

### L29 - rate limit / abuse (seat 1)
- **P3 (H-S1-1):** a retryable `55P03` lock timeout pages `critical` on the first failure of that payment. **verified_clean**:
  deliberate per plan 2.3 (a captured-but-unrecorded payment pages once; later failures are `warn` by dedup).
- **P3 (H-S2-1, shared with seat 2):** see L21.
- Clean: no caller can hold another user's advisory key; verify-payment's `consume_quota` (20 per 10 min) precedes the rpc;
  the webhook needs the HMAC; no unauthenticated path reaches the rpc or an alert insert.

### L21 - Edge Function semantic correctness (seat 2)
- **P3 (H-S2-1):** the failure path can take ~11 s (5 s lock timeout, then up to 6 s of alert round trips), and the
  `payment_alert.ts` header claimed the bounds kept the webhook inside Razorpay's response clock. **closed_in_commit**: the
  header now states the worst case and that a Razorpay timeout behaves like the 500 (retry, idempotent SQL); the clock check is a
  listed B2 flip item.
- Clean: OFF path vs `main` (only the import list, the new ON arm and `plainEndDate`), variable flow, no TDZ or missing await.

### L22 - schema-vs-payload parity (seat 2)
Clean: rpc argument names, `RETURNS TABLE` column names, `subscriptions` NOT NULL columns, the `alerts` columns and its
severity CHECK (076) all match.

### L23 - service-role authorization (seat 3)
- **P3 (H-S3-1, pre-existing):** verify-payment captures an authorized payment before the payment-owner check. **upstream_blocked
  -> OI-359**: the fix changes the OFF path that B1 keeps byte-identical to `origin/main`.
- Clean: `p_user_id` is never attacker-chosen (JWT user in verify-payment, HMAC-verified notes in the webhook); the function is
  unreachable by anon/authenticated (REVOKE by name + DO self-check).

### L40 - PII in telemetry (seat 3)
- **P3 (H-S3-2, pre-existing):** both writers log whole PostgREST error objects (row data incl. the signature) and Razorpay
  `notes`. **upstream_blocked -> OI-360**, same reason. The new ON-path lines and the alert row carry ids and a code only;
  `alert-critical-notify` does not forward `context_json` to Telegram.

### L2 / L35 / L14 - grants, reversibility, arbiter (seat 4)
- **P3 (H-S4-1):** the `ON CONFLICT` arbiter is verified from migration history only. **closed_in_commit**: plan step 6.2 adds a
  read-only `pg_constraint` read before either deploy.
- **P3 (H-S4-2, reminder):** the ledger pairing lands with the live apply, and 161 is immutable after it. **verified_clean**
  (Gate 14 and `check_migration_ledger_paired` enforce it).
- Clean: the rollback is complete; applying 161 before the code ships is inert; v25/v29 rollbacks never call the function; the
  lock key text matches 159/160; live PG 17 has every function used.

## Action items

- [x] H-S2-1 header corrected (this batch).
- [x] H-S4-1 arbiter read added to plan step 6.2 (this batch).
- [x] H-S3-1 filed as OI-359; H-S3-2 filed as OI-360 (docs/audit/open_issues.md).
- [x] H-S1-1, H-S4-2 verified clean (reasons above).

## Self-evolution note

Three reviewers (the Deno test agent, B-pass seat B, hermes seats 1 and 2) independently raised the same failure-path latency.
When a comment states a bound, a lens should check it against the WHOLE path (rpc + alert), not the module alone: the header was
true of `payment_alert.ts` and false of the writer that awaits it.
