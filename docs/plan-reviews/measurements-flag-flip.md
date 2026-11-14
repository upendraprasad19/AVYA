---
branch: measurements-flag-flip
date: 2026-10-16
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/measurements-flag-flip-bpass.md
---

# Plan-review record - L2b flag flip: `enable_body_measurements` default ON (`measurements-flag-flip`)

Plan: `docs/plans/measurements-flag-flip.md`. Parent plans: `docs/plans/coach-measurement-sheet-ui.md` (Landing B, which created the flag), `docs/plans/coach-measurement-surfaces.md` (Landing C) and `docs/plans/coach-measurement-sheet-l2b.md` (the umbrella that stated the flip's preconditions).

**Tier.** `platform`: `lib/core/services/measurement_flags.dart` has an exact-path platform rule (`docs/blast_radius.yaml:535`), declared above the `lib/core/services/**` account catch-all. This is the flip commit of a ship-dark flag, so CLAUDE.md 4.12.4 requires the full x2 review (not the `ship_dark_build` single round) and a B-pass. The change is one function plus tests and docs; there is no schema, Edge Function or migration.

**`bpass: accepted`** (2026-10-16, `docs/reviews/measurements-flag-flip-bpass.md`, with the same-dated entry in the code-review tuning history): two fresh context-blind Sonnet reviewers on the staged tree (A: production code and tests, with 15 proposed mutants; B: documents and claims), 21 findings, 0 P0, 3 P1, 6 P2, 12 P3, every one dispositioned in the review file.

## Rounds

- **Round 1** (v1 of the plan plus the draft diff; two context-blind Sonnet lenses under `docs/agent_brief_preamble.md` and an exhaustive read-only command list: R1A ground truth of every claim, R1B exposure and risk of a default-ON flag): 0 P0, 0 P1, 4 P2, 7 P3. The P2: a stale header comment and a flag-OFF rollover row that never set the flag (R1A); the stored `false` is erased by sign-out, which the plan did not say (R1A and R1B); the ledger and record the plan promised did not exist yet (R1A); no remote kill switch, so the audience statement had to be on the record (R1B). Adopted: the kill-switch paragraph with the sign-out loss and the founder's audience statement, the dev-panel row and toast reading `KILLED`, the rollover fixture, the line-number corrections.
- **Round 2** (the post-round-1 plan, same two lenses, fresh agents): 0 P0, 0 P1, 5 P2. R2A: three `default OFF` mentions the plan said it had covered (`lib/core/services/CLAUDE.md`, the Progress card line of `lib/features/profile/CLAUDE.md`, `docs/naming_conventions.md`) and the missing ledger; R2B: the web app builds from `main`, so merging exposes the production web app to every signed-in user, and the kill switch has no remote or web form. Adopted: all three docs fixed, the web statement added to the plan, the ledger created.
- **No round 3**: round 2 returned no P0 or P1 and reopened no design decision. The B-pass then found three P1 in the documents (the plan cited decisions that exist only on PR #117, the ledger and record were absent, and the published policy says things the build does not yet do); those were fixed in the same batch and are the reason the plan now carries a binding merge order.

`review_rounds: 2` counts the rounds on this unit's lineage; review #2 ran on the post-review-#1 plan (4.12.1).

## Ground truth verified

Reviewers were read-only; the coordinator re-verified every adopted claim: the getter's behaviour for each stored type (null, bool, int, double, String, List, Map) by the extended test loop and seven getter mutants, the one writer of the key (`dev_panel_screen.dart:275`), the readers, the sign-out clear (`user_repository.dart:1211`), the registry rule's line (`docs/blast_radius.yaml:535`) and its pin test, and the published privacy policy (fetched 2026-10-16: it names AVYA Fit, body measurements, Gemini and the other processors, retention, in-app deletion, a grievance officer, and "13 years or older" with a date of birth at sign-up).

## Decisions the founder made for this unit (chat, 2026-10-16)

Go on the flip; accept `LEGACY-PUSH`; OQ-L2a option 1 (accept); the app is in testing with internal testers' data only; the privacy policy is the founder's and is published at the same link. The age floor 13 and the "by continuing" sign-up consent are the founder's decisions for a separate branch (`age-floor-signup-consent`); the plan's merge order makes that branch land before this flip.
