---
branch: coach-workout-parity-server
scope: Coach workout parity Landing 2, server half (S0 deps seam in four cron functions, S1 distinct-day counting in the rank job, weekly-recalc, getPromotionStatus and the i-see-you-callout Saturday gate, S2 partial-day 9 pm / 8 pm push lines). S3 (the completion-tile tool) ships later on branch coach-workout-parity-tile with its own record.
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
mechanical_only: true
bpass: accepted
bpass_review: docs/reviews/coach-workout-parity-server-bpass.md
---

# Plan-review record: coach workout parity, server half

Plan: `docs/plans/coach-workout-parity-2-server.md` (rev 6). Every round used two context-blind Sonnet reviewers with an exhaustive read-only command list: seat A (ground truth, every file:line and claim checked against the code) and seat B (adversarial design and failure modes). Every round reviewed the revision produced by the previous round's fixes.

## Round 1 (rev 1, all of S1-S3)
Both seats returned `needs-changes`, with no P0.
- P1s:
  - the `ai-proxy` deploy row said `verify_jwt = true`, which would have made the gateway 401 every chat while the deploy reported healthy (A-F1);
  - a `log_set` and the tile in one turn let the reply promise a tile before the sets were saved (B-F1);
  - several guards were pinned only by source grep (B-F2).
- P2s: the capability gate was blind to identifier capabilities, the tool-count goldens were wrong, the 8 pm workout-name source was undefined, a stale-plan count was wrong, and the per-user failure scope was missing.
- Folded into rev 2.

## Round 2 (rev 2)
Both seats returned `needs-changes`, with no P0.
- P1s:
  - the planned handler tests could not be built, because each `index.ts` calls `serve` at import with no seam;
  - the same-turn suppression missed cross-round orderings;
  - one mutation (M38) could not redden anything.
- Coordinator correction between rounds: the suppression set is `{logSet}` only (a meal log neither surfaces nor suppresses the tile).
- Folded into rev 3.

## Round 3 (rev 3)
Both seats returned `needs-changes`, with no P0. One P1: the FC2 mutation could not be seen.
- P2s:
  - the deps seam would break `cron_auth_adoption_test.dart`;
  - the sanitizer had a dead fallback;
  - the tile was queued, then dropped;
  - the 9 pm partial line opened chat with no Complete control. Coordinator decision: it opens `/train`.
- The handler seam moved from a sibling `handler.ts` (about 1,170 moved lines) to the same-file `export handler` plus `if (import.meta.main) serve(...)` pattern, already live in 13 functions.
- Scope from round 4 on: S0-S2 only. S3 gets its own rounds on its own branch.

## Round 4 (rev 4, S0-S2)
Both seats returned `needs-changes`, with no P0 or P1.
- P2s:
  - the loader's date key was invisible to every test;
  - the static-import env claim was false;
  - no test covered the production default deps;
  - per-user attribution had no mutant;
  - a loader throw could stop every push. Fixed with a call-site guard.
- Seat B found the same rows-not-days over-count in `i-see-you-callout`. Per §4.2 it was added to S1, not filed.
- Folded into rev 5.

## Round 5 (rev 5, S0-S2)
Both seats returned `needs-changes`, with every finding tagged MECHANICAL. Seat B: "S0, S1 and S2 behaviour hold. The open items are test and mutation design."
- Fixed in rev 6:
  - the fetch-stub assertion was made robust to process-wide env leaks;
  - a presence-only source pin was added for the i-see-you call site;
  - fixtures now take their dates from `istDatesEnding(28)`;
  - expected-red lists were trimmed;
  - local fakes now provide `maybeSingle` and writes;
  - added mutant rows for truncation and bounds;
  - added a `getPromotionStatus` smoke turn.
- The round closes with `mechanical_only: true` (§4.12.6).

## Ground truth
Every seat verified file:line claims against HEAD `71f07c62` and the live-schema snapshot `backups/live_schema_columns.json`. Claims that cannot be checked from the repo are recorded as hard preconditions in the plan and are verified live and read-only before the deploy go: U2, the PostgREST hyphenated arrow-path select.

## B-pass
Accepted 2026-11-11: `docs/reviews/coach-workout-parity-server-bpass.md`. Two fresh Sonnet seats, split by slice, ran 20 mutants between them. No P0 or P1. Two P2 were fixed with mutation-proven tests: a failed completed-days read no longer fails the weekly-recalc tick, and both 28-day helpers are pinned at the IST-midnight boundary. One P2 was closed with evidence (a completed day is never deleted). One P2 is the recorded U2 deploy gate, and one is accepted residual R4.
