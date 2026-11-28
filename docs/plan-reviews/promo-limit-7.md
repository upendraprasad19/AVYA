---
branch: promo-limit-7
plan: docs/plans/2026-10-25-promo-check-limit-7.md
date: 2026-10-25
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/49b7a3133453-review.md
---

# Plan review - validate-promo check limit 20 to 7 per UTC-hour bucket (OI-366 follow-on)

Founder decisions (2026-10-25): after the OI-348 B6 walk on a free account the founder asked for "only 7
attempts and retry after an hour" and chose "7 per clock hour (smallest change)" (the fixed UTC-hour bucket,
which ends at :30 IST); commit, push, PR and merge for this branch; the deploy of `validate-promo` is a separate go.

**Review rounds.** Two context-blind rounds, two seats each, every seat limited to an exhaustive read-only command
list (no scripts, no network, no database statement). Round 1 (version 1, seats A tests and doc pins, B semantics and
rollout): 0 P1, 10 P2; none changed the design. Round 2 (version 2, the post-round-1 plan; seats C tests, doc pins and
gates, D rollout, hooks and semantics): 0 P1, 11 P2, none changed the design; each was a test-hardening, rollout or
bookkeeping detail and is folded into version 3 (the 30-minute-window mutant and the window-start literals, the
second-user ordering, the quota-census rule for `usage_counters` as well as the RPC name, the whole-tree `deno check`
and `deno test`, the deploy tree and the pinned rollback payload, the plan-review gate that runs only on the push to
`main`, `closes-oi: OI-406` on the board commit, the merged-but-not-deployed record on OI-366, the first-tap edge case of
the founder check). Version 3 was not sent to a third round: it adds no design change, and the folded text is
checked by the gates, the mutants and the B-pass below. Every reviewer claim was re-verified by the coordinator against
the file before it was folded in; none was rejected.

**Ground truth.** `consume_quota` is defined only by migration 128 (130 changes the ACL; 129, 132, 153 only call it);
the limit is a plain argument and a bucket row at `used >= p_limit` is refused at once without being touched.
`git log f58db308..HEAD` shows no change to `validate-promo/` or its imported `_shared` files, so the pre-change
closure is identical at f58db308 and at 25fb8a7f (the live bundle is compared at deploy time, not assumed). The 18:31:00Z
instant gives a 1740 s wait, "29 minutes". Tier: `validate-promo/**` account, `_shared/**` platform, the
`supabase/functions/**` catch-all platform (for `supabase/functions/CLAUDE.md`): max platform, re-measured on the real diff
with `blast_radius_from_diff.dart` (platform), no catastrophic path, so no hermes.

**Mutation proof (rule 21, self-attested, run after the final edit).** Eight mutants of `validate-promo/index.ts`, each
computed and anchor-asserted before it was written, restored with an equal sha256: limit 8 (3 Deno tests red + the Dart
pin), limit 6 (2 + pin), limit 20 (3 + pin), fixed `p_user_id` (only the second-user leg of the new test), a
`promo_codes` read before the counter (6 incl. the new test), a 30-minute window (3 incl. both new tests), a 2-hour bucket
formula (the next-bucket test; two real-clock tests also at an odd UTC hour), `p_limit` dropped from the call (3 incl.
the new test).

**B-pass.** `docs/reviews/49b7a3133453-review.md`: 0 P0 to P2, 5 P3, all accepted and handled (a glossary date that
outran the deploy, a test emulator that overclaimed fidelity to the SQL, the gateway-retry amplification now tracked as
OI-414 with a store-launch condition, the mutation and type-check evidence recorded, the commit-1 gate loop run).

**Verification.** Whole-tree `deno check` exit 0; whole-tree `deno test` 1448 passed and 2 failed (future-prediction and
re-engagement on :8000 AddrInUse, the known VPS quirk); `flutter analyze --no-fatal-infos` no warnings; full
`flutter test` (TZ=Asia/Kolkata, golden excluded) 11234 passed, 0 failed; the pre-commit gate loop exit 0 on commits 1
and 2.
