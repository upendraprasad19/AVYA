---
branch: payment-hardening
plan: docs/plans/2026-10-24-payment-hardening.md
date: 2026-10-25
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/59f092dc27a9-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-25-hermes-payment-hardening.md
---

# Plan review - payment hardening (OI-350/359, OI-360, OI-351, OI-366; U4 / OI-406 shipped first as PR #163)

Founder decisions (2026-10-24): target the payment items of the OI board, sequenced; U4 lock-down added; the
Telegram path deferred by the founder (out of scope); promo limit "every check, 20/hour"; the no-switch
exception for U0/U1 approved; switches default ON with a kill switch; U4 platform tier intended; rehearse, then
apply 163 live; "commit, PR, merge" for U4 and for this branch, one unit per commit with its own B-pass. Each
Edge Function deploy still needs its own go (plan section 6).

**Review rounds.** The plan was reviewed in three context-blind rounds: round 1, four seats (verify-payment,
webhook, order/promo, cross-cutting): 0 P0, 6 P1; round 2 on version 2, three seats: 0 P0, 2 P1, 11 P2; round 3,
a confirmation round on 2.1: 0 P0, 2 P1, 2 P2, 3 P3, none on the design. Every finding was re-verified by the
coordinator against code or live state before it was folded in (plan sections 9-11); one round-2 finding was
rejected as stale. Converged at version 2.2, which split U4 onto its own branch (§4.12.1).

**Ground truth.** Plan section 0 (2026-10-24): the live payment functions equal `main` byte for byte (eszip
`sourcesContent` compared), validate-promo differs only in its std import; live `verify_jwt` flags read with
MCP; `consume_quota` semantics and grants read from migrations 128/130. Re-checked during the batch: the
`promo_code_uses` UNIQUE(code, user_id) constraint, live (diagnose c7e3b1).

**B-pass, per commit (§4.3).** Every catastrophic commit carries its own staged, accepted review:
`4143cad5` U1 (docs/reviews/9d8fab4e9004-review.md), `0a8c090b` U0 (23830821b5bf), `b097d6fe` U2
(301b075809d5), `cbaa2dd9` U3 (f73e86b09ad0), `1a2f72e9` the hermes fixes (59f092dc27a9, two rounds, 10
findings, all fixed). The docs commits `e660e692` and `4466b87a` are not code.

**Hermes.** `docs/audit/2026-10-25-hermes-payment-hardening.md`, `verdict: accepted`: 4 Sonnet seats, lenses
L1 L2 L21 L22 L23 L29 L40, 19 findings (0 P0, 0 P1, 3 P2), 10 fixed in `1a2f72e9`, 3 filed (OI-409, OI-410,
OI-411), 5 kept with reasons.

**Open for the founder.** The six deploys, one go each (verify-payment, razorpay-webhook, create-razorpay-order,
validate-promo, founder-digest, telegram-admin-bot); the device checks on OI-348 (B5, B6, C9); OI-409's and
OI-411's live looks; OI-407 (switch removal after the live checks).
