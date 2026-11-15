---
branch: diet-supplements
date: 2026-11-15
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/diet-supplements-bpass.md
---

# Plan-review record — diet plan Unit 4: supplements, landing 4b-server (`diet-supplements`)

Plan: `docs/plans/diet-supplements.md` (revision 3). Execution mode (§4.12.7): inline, one worktree per landing: this one (`.claude/worktrees/diet-supplements`, based on `main` b463ceef) carries the plan and the SERVER half (landing 4b-server); the client half and migration (landing 4a) get their own worktree and their own record after this merges.

**Scope of this landing:** server only, no client file. `_shared/captain_manual.ts` gains `DIET_SUPPLEMENTS_MANUAL_PASSAGE` in SECTION 5 (one passage, every line conditional on `snapshot.profile.diet_supplements`) and its kill switch `DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES`, composed in `captainManual()` after the food-type and strategy switches. The dose vector `_shared/testdata/supplement_card.json` and `_shared/captain_manual_diet_supplements_test.ts`. Docs: naming rows, the functions CLAUDE.md row, OI-510's list, the snapshot contract entry, registry ranges re-anchored.

**Inert until an app sends the key:** `snapshot.profile.diet_supplements` exists only in an app build from landing 4a, only for a PRO adult with the Supplements switch on. After the deploy, every user gets today's coach (the passage is conditional on a key no snapshot carries; `weekly-report` bundles the manual but has no snapshot).

**Release order:** this PR merges first; then `ai-proxy` and `weekly-report` are deployed from the merged `main`, each with its own founder go and a rollback dry-run first (`.claude/skills/edge-function-deploy-rollback/SKILL.md`; the two live versions before the deploy are read back, as in Unit 3). Landing 4a (migration, client) follows.

## Rounds

| Round | Reviewer | Verdict | Material findings | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet on rev 1, ground truth read in `lib/`, `supabase/`, the food asset, CLAUDE.md | changes required | 2 P1 (the "verbatim" dose pin could not pass; the shake marker was not persisted or loaded) + 6 P2 + P3 | plan §10; rev 2 |
| 2 | context-blind Sonnet on rev 2 (post-round-1) | converged (no P0/P1) | 5 P2 (the manual lines were not all conditional; the snapshot key's value; on-then-off identity; the shake's reach unmeasured; source pins on `_generateFreshPlan`) + 8 P3 | plan §11-§12; rev 3; the reach was MEASURED on the real generator and the replacement rule adopted; this landing builds finding 1 and the vector; the rest is 4a |

The replacement rule was added after round 2 on measured data (plan §12); it belongs to landing 4a and is covered there by the reach test and that landing's own record and B-pass.

## B-pass

`docs/reviews/diet-supplements-bpass.md`, verdict accepted: three context-blind seats on `d5e1c9ca`, 24 findings, no P0 or P1; the passage header is bounded, the scoop budget stated, the doctor line first, an age condition added, the card-rows test made non-circular, the dose tokens carry unit and frequency, `weekly-report` inertness pinned. Mutants S1-S21: 21 of 21 red. 943 + new Deno tests green. Dispositions: plan section 13.
