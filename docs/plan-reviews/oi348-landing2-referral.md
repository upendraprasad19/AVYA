---
branch: oi348-landing2-referral
date: 2026-11-24
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/23ddbeedbc3c-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-24-hermes-oi348-landing2-referral.md
---

# Plan-review record — OI-348 Landing 2 PR B (B2 referral REGENERATE, migration 186)

Plan: `docs/plans/oi348-walk-fixes-landing2.md`, Unit B2, v4 CONVERGED. The plan was reviewed as one
document with four units (record for PR A: `docs/plan-reviews/oi348-landing2.md`); one
context-blind Sonnet seat per unit per round, each verifying every claim against the code and the
live project (`dedsavbjuwgarrhphgnl`, read-only). Every round after round 1 ran on the previous
round's revised text.

## Rounds (B2)
- **Round 1 (v1): `not_converged`.** 2 P1: the OUT column names equal to the table columns make
  plpgsql raise "column reference is ambiguous" (→ `out_code`, `out_expires_at`); two devices
  calling at once lose one result (→ per-user advisory transaction lock + a final re-select).
- **Round 2 (v2): `not_converged`.** 1 P0: `check_migration_ledger_paired.dart` blocks a commit that
  adds a migration without its ledger row, so an unapplied M2 cannot ride in PR B (→ M2 in its own
  PR C). 1 P1: M2 must wait for the web build carrying the RPC (→ Vercel READY + `main.dart.js` grep).
- **Round 3 (v3): `converged`** (P2s applied).

## Ground truth verified
Read: `supabase_service.dart` (`_generateNewCode`, callers), `invite_friends_sheet.dart`,
`redeem-referral/index.ts`, `sync_restore_completeness.dart`, `referral_repository.dart`
(`referrer_summary` token handling), `scripts/check_migration_ledger_paired.dart`, `vercel.json`,
`scripts/vercel_build.sh`. Live, read-only: `referral_codes` policies (SELECT own + INSERT own),
constraints (`UNIQUE(user_id)`, `referral_codes_code_key`), grants, columns, row count (3, 2
expired), `relforcerowsecurity` false, owner `postgres`.

## Execution
Inline, worktree `oi348-landing2-referral` (§4.12.7, decided at batch start). Catastrophic tier:
staged B-pass + Hermes pass + local full suite before the commit; migration 186 applied only after
both accept and the founder's go.

## B-pass
`docs/reviews/23ddbeedbc3c-review.md`: three context-blind Sonnet seats (A SQL, B client + sheet, C docs + registry + fallout) on staged hash 50c056340198. 18 findings (17 seats + 1 found by the coordinator while proving two of them), no P0/P1: 15 fixed with tests and mutation proof, 2 by design, 1 verified clean. Verdict accepted.

## Hermes
`docs/audit/2026-11-24-hermes-oi348-landing2-referral.md`: lenses L1, L2, L14, L35 (one Sonnet seat each) on the post-B-pass staged diff. 11 findings, no P0/P1: fixed, verified clean or recorded with reasons; 1 false alarm. Verdict accepted.
