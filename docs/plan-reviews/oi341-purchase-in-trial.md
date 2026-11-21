---
branch: oi341-purchase-in-trial
plan: docs/plans/oi341-purchase-in-trial.md
date: 2026-10-17
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d88f0a837e41-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-17-hermes-oi341-purchase-in-trial.md
---

# Plan review - OI-341 Piece A, the server-side stacking writers (dark)

Founder decisions: 2026-10-13 purchase must be enabled during the referral trial and the paid cycle starts when the current PRO ends (prepaid time stacks); 2026-10-16 "1, 2, 3 go approved" (start planning); 2026-10-17 "go" for Unit C then OI-341 (build). NOT covered by any of those: a commit, a push, a deploy (one function per go) or a merge.

## Review rounds

- **Rounds 1 and 2 (v1, v2): history of the UNSPLIT unit** (the order-function guard, both writers, the client door and copy). Round 1: 2 P1 (the helper's read-error fallback under-delivers paid time; the guard allow-list is fail-open), plus P2/P3. Round 2: 2 new P1 (the shipped Home expiry banner is already a purchase door for trial users, so the server deploy, not the client build, is the release; no kill switch makes the helper read a hard dependency of every payment), 5 P2, 5 P3. New material issues on a unit that large, so under CLAUDE.md 4.12.1 it was SPLIT and the smallest converged piece (this one, v3 = Piece A) shipped first.
- **Round 3 (the first review of v3, review #1 of this lineage):** 1 P1 (the kill switch had the wrong polarity: default-ON stacking put a new read and a new 500 path on every ordinary payment), 6 P2 (a thrown read must be caught; the helper can see the payment's own row; the fetch-level test design; round bookkeeping; a catastrophic blast-radius pin; Piece B's deploy-order sentence), 6 P3. Folded into v4.
- **Round 4 (the context-blind review of v4, review #2):** 0 P0/P1, 6 P2, 9 P3 (the "cannot affect an ordinary payment" claim overstated because the wrapper is not switch-gated; the SQL-NULL semantics of the in-memory PostgREST evaluator; a missing `user_id` filter statement and mutants; the interpolated payment id needs a strict format check; the golden request sequence needs a source). Folded into v4.1, which is plan-text and test-design only (`mechanical_only: true`).
- **B-pass** (`docs/reviews/d88f0a837e41-review.md`), two fresh context-blind Sonnet seats on the BUILT, staged tree: 0 P0, 1 P1 (a Dart source-grep contract test on the removed `serve(` wrapper), 3 P2 (the ON/OFF asymmetry of the payment id check; a flaky golden test; a DST-dependent test oracle), 8 P3. All fixed or recorded; the ledger rows are `BP-*`, `G10`.
- **Hermes pass** (4 Sonnet seats in one wave, whole-file reads of both redeployed functions, lens set L1, L2, L21, L22, L23, L29, L40 plus deployment): 0 P0, 0 P1. Fixed in this batch: the 23505 race arm could report an unstacked end when the winner's row could not be re-read; the webhook replay log interpolated the payment id before it was validated (check moved ahead of the replay block); the reconcile line now carries the plan and the amount. Filed as OI-350 and OI-351 (both on `origin/main`, the diff does not change them): the capture before the ownership check in `verify-payment`, and the 502 loop after an auto-capture followed by a failed insert. Recorded as Piece B flip preconditions: the webhook retry-timestamp assumption and an alert row on the read-failure path, the EST seal, the admin row-count views, concurrent different payments. The deploy steps were amended (explicit `verify_jwt`, the webhook probed with no Authorization header, flags read back, copy the rollback payload out first, never `--rollback` without `--dry-run`, deploy both before any secret).
- **Convergence, stated plainly.** v4.1 was NOT re-reviewed as a plan after round 4; the reviews that read the finished design were the B-pass and the hermes pass on the built tree. They found no P0 or P1 in the design; they found a stale source-grep test, an ON/OFF asymmetry in the id check, two test-hygiene defects, one ordering bug in a log line and a race-arm reporting gap, all fixed and mutation-proven (45 mutants, 44 killed, one equivalent). The founder approved the build with "go" on 2026-10-17.

## Ground truth

- Read in the worktree on 2026-10-17 at `origin/main` `45250e91`: both writers top to bottom, `_shared/subscription.ts`, `create-razorpay-order/index.ts` (the 409 guard, unchanged), migrations 006/010/052/094/140/152/154 for the `subscriptions` columns, constraints, policies and triggers, migrations 159/160 for the reward job (it reads `start_date` as the payment time), every Dart, Edge Function and SQL reader of subscription time (hermes seat 3), `.claude/emit_payload.js` and the deploy skill (hermes seat 4), the origin/main fixtures byte for byte (`git show origin/main:` equals the `.ts.txt` copies).
- Live, read-only, 2026-10-17 (MCP `execute_sql` on `dedsavbjuwgarrhphgnl`, project id confirmed first): the helper's SQL equivalent returns a real user's end date and NULL when excluding the row's own payment id. The PostgREST query STRING is proven only against the fetch-level fake.
- Replica: a disposable `rpoc-pgtest` container with migrations 159 and 160 applied ran the live-verify file, `SUMMARY ok=113 fail=0 skipped=0`, and a mutant of migration 160's copy of the job reddened V12 and V12b (removed afterwards).

## What this record does NOT claim

No deploy, no live payment, no boot of the two functions with the `import.meta.main` tail (stronger indirect evidence exists: `ai-media-proxy` v26 and six other deployed functions use it; the anon-key boot probe after each deploy is the proof), no live proof that PostgREST accepts the helper's `.or()` string, no evidence about Razorpay's retry timestamps, and nothing about Piece B (the order function's door, the switch flip, the alert row, the client copy). The full CI run on the PR has not happened (the local full Flutter suite had one failure, since repointed; the local Deno suite has two environmental `AddrInUse` failures on :8000).
