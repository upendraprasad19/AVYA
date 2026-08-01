---
branch: re-engagement-prefilter
date: 2026-08-01
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/6d2c1d8cc8da-review.md
hermes: accepted
hermes_review: docs/audit/2026-08-01-hermes-reengagement-prefilter.md
---

# Plan review — re-engagement-prefilter

Unit 5 of the OI-25/44/45/46/48/50 batch. Closes OI-48, whose scope two prior
board corrections had already narrowed from 3 functions to 1: `re-engagement`'s
Path B silent-user fallback fetched every non-deleted user, then issued up to 3
sequential per-table point queries per candidate (1 + 3N round-trips per daily
tick, unbounded with user count). Replaced with a single Postgres RPC
(`find_reengagement_silent_candidates`, migration 117) expressing the same
absence check as three `NOT EXISTS` anti-joins.

## Rounds

| Round | Scope | Outcome |
|---|---|---|
| Round 1 | Context-blind, full-diff + live DB | 7 findings (F1-F7). Core code verified correct in every dimension tested; documentation not accurate enough to merge at catastrophic tier. All fixed. |
| Round 2 | Context-blind, on the POST-round-1 hardened diff | 7 findings (N1-N7). Confirmed all 7 round-1 fixes correct with independent evidence; found 1 blocker (ledger/apply ordering), 1 lint regression (`search_path`), 5 precision items. All fixed or dispositioned. |
| B-pass | 5-lens adversarial, staged diff | 3 findings — all documentation-accuracy (a backwards date claim, a wrong count, a rollback-coupling gap). Code independently re-executed live and confirmed correct. All fixed. |
| Hermes | 8 lenses (L1/L13/L21/L23/L31/L34/L35/L37) | 9 findings: 1 P1 (filed OI-79), 3 P2, 5 P3, 5 false_alarm. One lens **refuted a fix from the previous round**. Zero ship-blockers. |

## Why this is converged rather than merely green

Four rounds is more than the §4.12 minimum, and §4.12.1 warns that
successive rounds surfacing *new* material issues signals a unit that is too
large. That test was applied deliberately rather than ignored, and this unit
passes it: the **core change was never the thing being corrected**. Every
round independently re-verified the RPC's anti-join semantics, parameter
types against live schema, privilege-grant mechanics, caller completeness,
index support, and rollback safety — and every round found them correct.
What each round corrected was progressively narrower and further from the
change itself:

- Round 1: my documentation overclaimed an RLS fact.
- Round 2: a missing `search_path` and an ordering constraint on the commit.
- B-pass: a date stated backwards and a count off by one.
- Hermes: an *observability* gap in a tradeoff prior rounds had cleared on
  correctness — and one bad fix from the round before it.

That is a convergent sequence, not a divergent one. Splitting here would
have split a change whose substance was never in dispute.

## The finding worth recording

Hermes L21 refuted L34's F3 from the immediately-preceding round. L34
reported that a `markProactiveSent` throw double-counted a user into both
`sent` and `errors`; a wrapper plus a `markFailures` counter were written
against that claim. Reading the callee settled it —
`_shared/proactive_dedup.ts:87-95` wraps its whole body in try/catch and
only `console.warn`s ("Non-fatal on failure (the push already went out)").
It cannot throw. The double-count was unreachable, and the fix was worse
than the non-bug: `mark_failures` could only ever be `0`, so emitting it
would have affirmatively asserted "dedup bookkeeping never failed" while
real failures are silently swallowed inside the helper.

Fully reverted. The replacement test pins the **premise** rather than the
shape — it re-reads `proactive_dedup.ts` and fails if the helper ever grows
a throwing path. Recurrence class:
`feedback_audit_verifier_cannot_trust_own_subagent` — the finding quoted the
call site accurately and reasoned wrongly about the callee, and the fix
shipped before the callee was read.

## Ground truth

Everything asserted here was checked against live state, not inferred:

- Migration 117's DDL run in a rolled-back transaction against
  `dedsavbjuwgarrhphgnl` — **11/11 cases `ok`**, re-run after every change to
  the DDL (`test/sql/reengagement_silent_candidates_verify.sql`).
- Parameter types checked against `information_schema.columns` before the
  migration was finalized (a first draft had `p_cutoff_date timestamptz`
  against `date` columns — caught pre-apply).
- `find_orphan_chat_media`'s pre-fix grants confirmed by live
  `has_function_privilege` (anon=true, authenticated=true) — the premise of
  Part 2.
- The RLS "not a live leak" conclusion re-derived from live `pg_policies`
  twice after two successive drafts stated it imprecisely.
- Migration creation dates from `git log --diff-filter=A`, after the B-pass
  found the causal claim was backwards.
- `prosecdef` for all 9 functions migrations 090/091 revoked (the "8" in an
  earlier draft was wrong).
- Query plan via live `EXPLAIN (ANALYZE, BUFFERS)`; index support confirmed
  on all three anti-join tables and on `users.last_active_at`.
- PostgREST's row cap confirmed by an actual 206 + `Content-Range` response.
- Deployed `re-engagement` confirmed to be v10 (old code) by grepping the
  live bundle, establishing the migration-before-deploy ordering is safe.

## Residuals, stated

- **Migration 117 and the Edge Function deploy are NOT yet live.** Both need
  their own explicit authorization per §4.3 (plan approval ≠ deploy
  approval). Order is load-bearing: migration first, then the deploy —
  deploying first would 500 every Path-B-eligible tick. `touched_layers_checked`
  tiers 5/6 are marked `pending_explicit_authorization` rather than
  `fixed_in_this_batch` to keep that visible.
- **OI-78** (P3) — 3 more public-schema RPCs carry the same unrevoked
  PUBLIC-default EXECUTE grant. Not folded in: they were not the reference
  pattern this migration was designed against, each needs its own
  caller/RLS verification at the same rigor, and bundling them would dilute
  it. Recommends a structural allowlist gate over a 5th one-off fix.
- **OI-79** (P1) — un-ranged PostgREST reads truncate at 1000 rows on both
  candidate paths. Pre-existing; this batch strictly improves the Path B
  case and adds loud saturation detection to both, but the pagination fix
  spans cron functions this batch does not otherwise touch.
- `index_test.ts` has no malformed-row case (Hermes L37, PARTIAL) —
  deliberately not added, because `RETURNS TABLE` plus a `uuid NOT NULL`
  column make the malformed shape unproducible by this writer; a test for it
  would pin the mapper's tolerance, not production behavior.
