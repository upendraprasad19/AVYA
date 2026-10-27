---
branch: fix-e2e-cosmetics-copy
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/e2e-cosmetics-copy-recovery-review.md
hermes: accepted
hermes_report: docs/audit/2026-06-25-hermes-e2e-cosmetics-copy.md
---

# Plan-review record — fix-e2e-cosmetics-copy (Unit C + completeness recovery)

§4.12 plan-review record, written 2026-06-25 as the honest catch-up. Unit C
(`66143a4`, merged `c553ab0`) shipped **account**-tier WITHOUT this record — the
blast-radius was misclassified `feature` by a buggy positional `blast_radius_from_diff`
invocation (`feedback_mistake_blast_radius_positional_mode.md`). The CI keystone gate
`check_plan_review_record_exists.dart` correctly red-flagged the merge; `c553ab0`'s run
stays red as the truthful artifact of the miss. The deep review (below) + the two
completeness fixes it surfaced land as a fix-forward commit on `main`.

**Diagnoses:** OBS-11 `docs/diagnoses/2026-06-23-nutrition-target-carb-dualname-c8a1f4.md`;
Unit C `docs/diagnoses/2026-06-23-e2e-cosmetics-copy-e5c1a2.md`.
**Plan:** `~/.claude/plans/lets-tackle-them-all-delightful-cascade.md` (checkpoint 2026-06-25).

## Reviews (independent, context-blind) — 3 rounds
- **R1 — Explore-locate + my ground-truth verification** of each cosmetic/copy site;
  corrected Explore-agent hallucinations; verified every file:line against code.
- **R2 — fresh context-blind Sonnet B-pass (5 lenses)** on `66143a4`: found the
  `edit_profile_screen.dart:1595` `full_name` 2nd-writer (P2, REAL); over-called a
  `titleCaseName` surrogate-pair "corruption" (later refuted).
- **R3 — 4-lens Opus Hermes** (field-drift completeness · Unicode/i18n · UI render-safety ·
  state/side-effects): found the `user_repository.ensureComputedTargets:217` carb
  singular-only **write-back** (P1, REAL — the OBS-11 sibling Unit B missed); EMPIRICALLY
  REFUTED the surrogate false-alarm (Dart `String[0]`+`substring`+concat round-trips
  non-BMP losslessly); verified all 4 UI fixes provably clean.

## Ground-truth audit (verified, not asserted)
Enumerated EVERY `full_name` writer (8 sites: 2 raw-input [onboarding ✓, edit_profile → fixed],
2 propagate-stored, 1 external OAuth bootstrap, 1 false-positive `_stepLabel` switch, 2
intermediate route-extras) and EVERY carb-target reader (`nutrition_provider` ✓, `home_provider` ✓,
`user_repository:217` → fixed, all others plural-correct). Read `user_repository.dart:210-265`,
`bmr_calculator.toMap:309`, `edit_profile_screen.dart:1522/1595`,
`auth_session_bootstrapper.dart:206/232`.

## Verdict
**Converged.** Two real completeness misses (one per unit) fixed; one false-alarm refuted; all
UI fixes clean. Fixes: `edit_profile` title-case (P2), `user_repository` carb dual-name + `toMap`
plural (P1), plus the `blast_radius_from_diff` positional-ref guard (the tooling foot-gun that
caused the miss). Tests: `title_case_name_test` (+2), `nutrition_target_carb_dualname_test` (+2),
`blast_radius_positional_ref_guard_test` (new) — all green; analyze clean.

**bpass: accepted** — `docs/reviews/e2e-cosmetics-copy-recovery-review.md`.
**hermes: accepted** — `docs/audit/2026-06-25-hermes-e2e-cosmetics-copy.md`.
