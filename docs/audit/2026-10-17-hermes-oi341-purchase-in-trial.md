---
hermes_pass_id: 2026-10-17-hermes-oi341-purchase-in-trial
ran_at: 2026-10-17T00:00:00+05:30
batch_scope: branch oi341-purchase-in-trial, built and staged tree (later committed as 8be9371d), whole-file reads of supabase/functions/verify-payment/index.ts and supabase/functions/razorpay-webhook/index.ts
lens_set: [L1, L2, L21, L22, L23, L29, L40, deployment]
agents_dispatched: 4
model_deviation: "Sonnet, one wave of 4, not the skill's Opus default: the founder's standing rule (2026-09-26, 2026-10-07) overrides it."
findings_total: 11
findings_by_severity: { P0: 0, P1: 0, P2: 2, P3: 6, informational: 2, confirmation: 1, false_alarm: 0 }
verdict: accepted
---

# Hermes E-pass: OI-341 Piece A (the server-side stacking writers, dark)

## Provenance

This file was written on 2026-10-19, after PR #124 merged. The pass itself ran on
2026-10-17, and its findings and dispositions were committed at the time in two
places that this file now consolidates, without adding or changing a finding:

- `docs/plans/oi341-purchase-in-trial.md` section 8, paragraph "Hermes pass".
- `docs/audit/oi341-purchase-in-trial.closure.yaml`, rows `H-S1-1` to `H-X1`.

Why this file exists: the plan-review record named those two places in prose in its
`hermes_report:` field. `scripts/check_plan_review_record_exists.dart` reads that field
as one path under `docs/audit/` that must exist and carry `verdict: accepted`, so the
main CI "Plan-review record" job failed on the merge commit `85e8f76a` (run
39146314279). Every other job on that run was green. The record now points here.

## Summary

Four Sonnet seats ran read-only in one wave. Each read both redeployed functions as
whole files, not just the diff, because the unit of risk in a redeploy is the bundle
that ships. The seats returned 0 P0 and 0 P1.

Five findings were closed in the batch: three code fixes, all mutation-proven, and two runbook or deploy-step amendments. Two pre-existing defects,
neither changed by the diff, were filed as OI-350 and OI-351. Two findings are
preconditions for the Piece B flip. The rest were verified clean.

## Findings by seat

### Seat 1: L21, L22 (Edge Function semantics, contracts)
- **H-S1-1, P3, closed_in_commit.** The 23505 race arm in `verify-payment` could report
  the unstacked `now + days` when the winning row could not be re-read (switch ON only).
  - Fix: `canonicalEndDateIso` is seeded from the stored value before the insert.
  - Proof: a race-re-read-failure test, and mutant M23 killed.
- **H-S1-2, P3, verified_clean.** The webhook's `expires_at` on a replay or a 23505 race
  is the call's own computed value. This is identical on `origin/main`, and nothing
  reads it: Razorpay ignores the body.
- **H-S1-3, P3, blocked_on_user (filed OI-351).** An auto-capture followed by a failed
  insert loops 502. The same shape exists for any insert failure on `origin/main`.

### Seat 2: L23, L40 (service-role reach, PII and logs)
- **H-S2-1, P3, blocked_on_user (filed OI-350).** `verify-payment` captures the payment
  and echoes its status before the ownership check. This is on `origin/main` and the
  diff does not change it.
- **H-S2-2, P3, closed_in_commit.** The webhook replay log interpolated the payment id
  before it was validated.
  - Fix: the format check now runs before the replay block.
  - Proof: a stale-delivery test, and mutant M37 killed.
- **H-S2-3, informational, closed_in_commit.** Two hazards while the switch is ON:
  - An unparseable `end_date` fails every payment for that user.
  - A secret pasted with a trailing newline stays OFF.

  Both are written into `payment.md` rule 9, runbook items 1 and 2.

### Seat 3: L1, L2 (writer/reader, data exposure)
- **H-S3-1, informational, upstream_blocked.** For a stacked user, some display and
  reporting surfaces are wrong or double-count: the Profile EST seal, the optimistic
  local end date, and the admin and Telegram row-count views.
  - Unreachable while the 409 order guard stands.
  - Reopens with Piece B.

### Seat 4: L29, deployment
- **H-S4-1, P2, upstream_blocked.** The webhook's retry safety net assumes Razorpay
  re-stamps `created_at` on a retry, and nothing alerts on a payment that was captured
  but not recorded. Both are Piece B flip preconditions (runbook item 4).
- **H-S4-2, P2, closed_in_commit.** The deploy tool defaults `verify_jwt` to true (OI-334).
  The deploy steps were amended to:
  - pass the flag explicitly;
  - probe the webhook with no Authorization header;
  - read both flags back from the management API.

  The steps were applied on 2026-10-18 (`verify-payment` v25, `razorpay-webhook` v29).
- **H-S4-3, P3, closed_in_commit.** Two fixes:
  - The archive prune could delete the pre-change payload, so the steps copy it out
    first.
  - The reconcile lines now carry `plan=` and `amount_paise=` (mutants M38 and M38b
    killed).
- **H-X1, verified_clean.** Seat 4 confirmed the following:
  - The `import.meta.main` guard is already used by `ai-media-proxy` v26 and six other
    deployed functions.
  - `emit_payload.js` bundles only `index.ts` plus `_shared/subscription_stacking.ts`.
  - Switch OFF differs from `origin/main` only in the wrapper and the 400 on a
    malformed id.

## Action items

Every finding is terminal, and the ledger is the source of truth for each disposition:

- 5 closed_in_commit
- 2 blocked_on_user (OI-350, OI-351)
- 2 upstream_blocked (Piece B)
- 2 verified_clean
