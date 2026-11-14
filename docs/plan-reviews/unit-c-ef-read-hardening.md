---
branch: unit-c-ef-read-hardening
date: 2026-07-08
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/unit-c-ef-read-hardening-bpass.md
---

# Plan-review record — Unit C: Edge-Function unchecked-read hardening (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
(getProgressSummary/getPromotionStatus on the ai-proxy coach path; 8 EF redeploys). Not catastrophic → no Hermes.

## Scope
Harden 12 Edge-Function reads that destructured `.data` without capturing `.error` (§2.24 — a silent query
failure coerced into empty/default data → silently-wrong effect: coach "0 workouts"/wrong promotion status;
disabled notifications sent anyway; active user re-engagement-nudged; wrong rank state / blocked promotion).
Diagnose `a7e2c4`; closure YAML `docs/audit/unit-c-ef-read-hardening.closure.yaml` (12 findings, all
closed_in_commit). Also adds the first-ever Deno CI job + fixes 4 pre-existing red Deno tests.

## Review arc (2 rounds; §4.12) — this record is NOT the plan-level seed
Per the discipline that each branch runs its OWN ≥2 review of its OWN content (not a citation of the
plan-level review), the two rounds below EACH examined this branch's 12 sites directly:

- **Round 1 — design review, ×4 context-blind (converged).** The design of these EXACT 12 sites (which
  site, throw-vs-skip-vs-sentinel per site) was reviewed across four independent context-blind rounds, each
  reading the live code at each cited file:line. It corrected: the completeness (5→12 sites — added
  re-engagement, getPromotionStatus, the rank-cron reads); the rank mechanism (the `-1.0` sentinel, verified
  against the `<` gate at `rank_engine.ts:88`, NOT a bare throw that would abort the whole cron); the sites
  6/7 PGRST116 send-vs-skip (a naive skip would suppress a paying user's expiry reminder); the R4 P0 that a
  bare try/catch wrap around a swallowing read is INERT (the read itself must be converted to capture+skip);
  and the Deno-CI-gap (the behavioral tests never ran in CI). `ground_truth_verified: true` — every
  load-bearing claim (fiber, the 6-emitter surface [OPT-D, split out], the `<` operator, the PGRST116 shape)
  was re-read against the actual files by me, not trusted from subagent prose (§2.9).

- **Round 2 — implementation B-pass, context-blind (accepted).** A fresh reviewer traced the IMPLEMENTED
  staged diff (all 12 sites, both test changes, the CI job, the counters, the loop composition) against the
  actual files. Verdict SHIP-WITH-FIXES, **no P0/P1**: every fix captured AND acted on per its kind; PGRST116
  the right way round; `-1.0` on the error path only; the `:167` continue preserved; ceremony assertions
  byte-exact (no fabrication); no unintended files. Two P2 advisories, both FOLDED: P2-1 (getPromotionStatus
  type-clean + added to the CI `deno check`), P2-2 (full Deno suite verified locally — 223 passed / 0 failed).
  `docs/reviews/unit-c-ef-read-hardening-bpass.md` (`verdict: accepted`).

## Implementation verification
- `dart run scripts/check_schema_column_refs.dart` → 810 refs, 0 drift (column-neutral).
- Cron `logCronStart`/`logCronEnd`/auth idioms intact in all 7 edited crons.
- Deno: full suite **223 passed / 0 failed**; the 3 CI-type-checked files (getProgressSummary,
  getPromotionStatus, rank_engine) `deno check` green; the 6 behavioral tests pass.
- Diagnose-doc + closure YAML validators green.

**Verdict: converged.** No P0/P1 across ×4 design + 1 implementation review; all P2s folded.
