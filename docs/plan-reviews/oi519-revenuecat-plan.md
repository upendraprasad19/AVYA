---
branch: oi519-revenuecat-plan
date: 2026-11-24
blast_radius: catastrophic
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/f415470375b9-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-24-hermes-oi519-play-billing.md
---

# Plan-review record: OI-519 Android PRO through RevenueCat + Google Play Billing (+51)

Plan: `docs/plans/2026-11-23-revenuecat-play-billing-51.md` (v9). ADR-0022. Tier L, blast radius catastrophic (a new
writer of the PRO entitlement, migration 182, SECURITY DEFINER functions, delete-account).

Six context-blind Sonnet plan rounds, each on the previous round's revised plan:
- Round 1 (v1): 19 findings (5 P1), not converged; folded into v2 (plan section 14).
- Round 2 (v2): 10 findings (2 P1), not converged; the client-grace P1 was solved by deleting that mechanism (section 15).
- Round 3 (v3 changes): 7 findings (1 P1, in the new window); folded into v4, converged (section 16).
- Round 4 (v5, the founder's Q1 = B defer mechanism and its seams), rounds 5 and 6 (v6, v7): folded (section 17);
  v8 converged.

Ground truth: plan section 1 facts verified at `8eff2037` and read-only against the live project
`dedsavbjuwgarrhphgnl`; migration 182 had its own pre-apply review (section 22) and was applied live at L1 with the
founder's go (section 23; live check: all 6 functions match the file, grants locked to service_role, 0 Play rows).
RevenueCat response shapes checked from its docs (U0, section 18).

Code reviews (each a staged, accepted review file; every finding checked by the coordinator, every fix mutated):
- 182 + U3: `docs/reviews/ec073c981012-review.md` (12 findings; section 24).
- U4 + U5 + U6: `docs/reviews/667e533689bd-review.md` (3 rounds, 20 findings, 27 mutants; section 27).
- Hermes fixes: `docs/reviews/f415470375b9-review.md` (2 rounds, 13 findings, 36 mutants; section 28).

Hermes: `docs/audit/2026-11-24-hermes-oi519-play-billing.md` (4 Sonnet seats, 7 lenses incl. the live sequence;
0 P0/P1, 3 P2, 15 P3; 16 fixed, 2 verified clean; recorded `model_deviation`: Sonnet under the founder's rule).

Not covered by this merge, each needing its own founder go: L2 deploy of the 10 functions from merged `main` (switch
OFF) and the two database drafts (hourly reconcile cron, the start_date fix), L3 test event, L4 switch ON, L5 the +51
version bump and `/build-apk --bundle --purchase-mode play_billing`.
