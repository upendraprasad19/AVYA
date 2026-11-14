---
branch: promo-codes-server-only
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/83b0e3c919aa-review.md
tier: platform
date: 2026-10-24
---

# Plan review — promo-codes-server-only (OI-406, migration 163, diagnose a6c2e9)

**Scope:** unit U4 of `docs/plans/2026-10-24-payment-hardening.md` (section 3 U4), split onto its own
branch in plan version 2.2 under §4.12.1 so the live exposure closes first and alone: migration 163 drops
the `promo_codes` policy "Anyone can read active promo codes" and revokes ALL from PUBLIC, anon and
authenticated. No client or Edge Function code changes.

**Review rounds.** The plan was reviewed in three context-blind rounds (round 1: four seats, 0 P0, 6 P1;
round 2 on version 2: three seats, 0 P0, 2 P1, 11 P2, the second seat covering order/promo/migration;
round 3, a confirmation round on 2.1: 0 P0, 2 P1, 2 P2, 3 P3, none on the design). Every finding was
re-verified by the coordinator against code or live state before it was folded in (plan sections 9 and
11). U4's round-2 question (is the REVOKE complete: views, publications, definer functions, column
grants?) became live-verify cases P4, P8, P9 and P15.

**Ground truth.** Pre-apply live read 2026-10-24: anon and authenticated each held all 8 table
privileges (grantor postgres), the one SELECT policy, RLS enabled; an anon-key count-only request answered
206 `*/3`; live verify ok=10 fail=6 (P1-P5, P14), as predicted.

**B-pass.** `docs/reviews/83b0e3c919aa-review.md`: 12 findings (0 P0, 2 P1), all accepted and fixed,
`verdict: accepted`. Finding 9 (the change drops an RLS policy yet grades platform): **the founder confirmed
"platform is intended" on 2026-10-24.** No user data is deleted; only the client read path to a
server-only table goes away, and the inline rollback restores it.

**Live apply (founder go, 2026-10-24).** Rehearsal 16 of 16 ok with nothing persisted and 0 locks;
`apply_migration` cloud version `20261024121637`; post-apply verify 16 of 16 ok; anon-key read 401 / 42501.
Detail: the diagnose-doc's "Apply record" and the `backups/applied_migrations.json` entry for 163.

**Open for the founder.** A signed-in promo check in the app (validate-promo) after the apply; the
service-role read it depends on is proven at the database (P10, P13: 3 of 3 rows).
