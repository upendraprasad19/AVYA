---
branch: oi469-formcues-active
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi469-formcues-bpass.md
---

# Plan review — oi469-formcues-active (getFormCues skips retired exercise rows, OI-438 / OI-469)

Plan: `docs/plans/2026-11-13-oi469-formcues-active.md` (rev 3 plus the build). Tier L (Edge Function under `_shared/**`,
deployed through `ai-proxy`), blast radius platform. The live `ai-proxy` deploy is NOT in this branch and needs its own
explicit founder go; OI-438 and OI-469 stay OPEN until it.

## Review rounds

Three rounds, each one fresh context-blind Sonnet seat with an exhaustive command list (read-only, no scripts, no
database). Rounds 1 and 2 on the PLAN, round 3 on the BUILT diff (the B-pass; there was no separate round on the diff
besides it).

- **Round 1 (plan rev 1): not converged, 0 P0 / P1, 4 P2, 6 P3.** The plan's strict `.eq("is_active", true)` would have
  made 56 of 64 retired-only names answer `found: false` with no recorded decision (the seed says such a row "keeps
  its own cues, which are right for its own name"); the live check could not work (tool results are not logged in
  `tool-loop.ts:621-635`, and the four same-name pairs already carry identical cues); the rollback recipe would have
  silently set `verify_jwt=true` (skill 6.13); the registry and two comments went stale. Every finding was checked
  against the repo or live before use. Rev 2 swapped to a prefer-active design.
- **Round 2 (plan rev 2, the post-round-1 plan): not converged, 0 P0 / P1, 4 P2.** OI-438 is the same defect and was
  missing; the "design intent" reading of the seed comment was overstated (the C2 plan treats the filter as the
  follow-up fix, and only about 14 of the 56 retired names resolve in the Hive client); the rollback-by-deactivation
  case (migration 164) was missing from the trade-off; the rollback recipe was impossible as worded (`--rollback`
  carries no `verify_jwt` argument). All four were plan text, none a design defect; the one real design call was put to
  the founder (AskUserQuestion, 2026-11-13) who chose the STRICT filter. Rev 3 applied the findings and the decision.
  Rev 3 itself had no further plan round; the build followed, and the third round reviewed it.
- **Round 3 (the BUILT diff `origin/main...HEAD` at `2b5e3dea`, CI green on `291ccba1`, the B-pass): converged, 0 P0 /
  P1 / P2, 4 P3**, all documentation (a misattributed provenance, a third outcome class missing from the impact
  statement, an ungated stale OI cite, tense and rollback wording), all fixed in the follow-up commit. Nine mutations by
  the seat reproduced the author's counts; two survivors are equivalent mutants (recorded in the diagnose). See the
  review file's own Tuning entry.

## Ground truth

Every figure and line cited in the plan was re-derived from the repo or the live project (`dedsavbjuwgarrhphgnl`,
read-only) before use: 934 rows = 870 active + 64 inactive, 0 NULL `is_active`; 4 same-name pairs; 56 of 64 retired
rows with no live equal-or-containing name (the other 8: the 4 pairs and 4 contained names); 0 rows in
`template_exercises`, `workout_logs`, `workout_log_exercises` pointing at an inactive row; foreign keys read from
`pg_constraint`. The reviewers reproduced the repo-derivable numbers independently.

## §4.6 note (no kill switch)

The change is one filter on a read in a tool the coach may call; it adds no code path to gate, and rollback is a
revert plus an `ai-proxy` redeploy through the SHA-pinned recipe (skill 6.13). Not a payment / sync / auth / plan-engine
change; no ship-dark tier is claimed.
