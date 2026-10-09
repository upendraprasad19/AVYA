---
branch: opt-e-rank-cron-batch
date: 2026-07-08
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/opt-e-rank-cron-batch-bpass.md
---

# Plan-review record — OPT-E: rank-cron N+1 batch pre-fetch (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
(`evaluate-rank-promotions` cron + `_shared/rank_engine.ts`; 1 EF redeploy). Not catastrophic → no Hermes.

## Scope
`evaluate-rank-promotions` (nightly cron over every signed-up user) issued 3 separate per-user Supabase
queries inside its loop (`user_progress`, `rank_promotions`, `user_profile.current_rank_code`) — 3×N
queries/tick. Pre-fetches all three in chunked batches (`BATCH_SIZE=100`, mirroring the existing
`weekly-recalc/index.ts` precedent for the identical query shape) before the loop, via new pure grouping
functions in `_shared/rank_engine.ts` (`buildUserProgressMap`, `buildRankPromotionsMap`,
`buildCurrentRankMap`) plus a `fetchInChunks` helper in `index.ts`. Two reads deliberately stay per-user: the
`workout_logs` COUNT (batching needs a GROUP BY RPC + a migration-sequencing risk) and `completionRateOverWindow`
(rarely invoked, per-rank-varying window). Pure efficiency — no user-facing behavior change. Per the OPT-C
precedent (`perf(db): add covering indexes...`, ff1c793), no diagnose-doc/closure-YAML: those apply to bug
fixes (rule 22) and ≥4-item audits (§4.2) respectively, and this is neither.

## Review arc (2 rounds; §4.12) — this record is NOT the plan-level seed
Per the discipline that each branch runs its OWN ≥2 review of its OWN content, both rounds below examined
this branch's actual diff directly (not the bundled Unit C/OPT-B/D/E/F plan-level ×4 rounds, which only
seeded OPT-E's design — the per-user-COUNT-stays-per-user default, in particular, traces to that seed).

- **Round 1 — design + implementation, context-blind (converged with fixes).** Independently re-verified the
  UNIQUE(user_id) constraints on `user_progress`/`user_profile` (migration 001) and UNIQUE(user_id, rank_code)
  on `rank_promotions` (found the code cited migration 040 — wrong; the real DDL is in 039) directly against
  the migration files, confirmed all batched columns exist live, confirmed the null/absent Map semantics
  match the old per-user queries exactly, and formed an independent view that the failure-isolation
  blast-radius increase (batch failure aborts the whole tick vs. old per-user skip) is an acceptable trade —
  citing that the old code's silent `logCronEnd(..., "success")` on a total outage was a *worse*, less honest
  hidden defect. Found 3 real (minor) issues: the migration-040 citation, a stale SoT `line_range` the
  pre-fetch insertion had shifted, and a design inconsistency — `weekly-recalc` chunks the identical query
  shape at `BATCH_SIZE=100` and this diff originally didn't. All 3 folded: citation corrected, chunking added
  (matching the in-repo precedent rather than just documenting an exemption, since the fix was cheap and the
  pattern already proven), SoT line-range updated.

- **Round 2 — post-fix verification, context-blind (converged with fixes).** Reviewed the hardened diff,
  specifically scrutinizing the brand-new `fetchInChunks` chunking code round 1 never saw (chunk-slicing
  off-by-one, stop-on-first-error, partial-data discard-on-error, chunk-boundary user-splitting — all
  confirmed correct by direct control-flow read) — and caught that round 1's OWN SoT line-range fix had
  landed on the WRONG block (272-293, the ceremony-insertion loop, not the denorm-sync block at what was then
  308-329) because a subsequent edit in the same round (adding the chunking helper) shifted the file again
  after the citation was written. Also flagged that the 3 new `fetchInChunks` call sites are invisible to
  `check_schema_column_refs.dart` (the gate's own header documents `.from(<variable>)` as unvalidated by
  design) — a real coverage gap, though the runtime failure mode is fail-loud (whole-tick abort), not
  silent-degrade. Both fixed: the line-range was re-derived via a direct `grep` against the FINAL file state
  (as the last edit in the batch, to avoid re-invalidating it with a subsequent edit) and landed at 319-340;
  a doc-comment caveat was added to `fetchInChunks` noting the gate blindness explicitly.

**Process note:** round 2's findings were a self-inflicted citation error (fixed and re-verified via direct
tool inspection, not by re-dispatching a third agent) plus a documentation gap — not a new defect in the
underlying batching/chunking design, which round 2 independently re-confirmed sound end-to-end. That is the
convergence signal (findings shrinking in substance), not the "keep finding new material issues → split it"
signal.

## Implementation verification
- Deno full suite: **244 passed / 0 failed** (includes 9 new tests for the 3 grouping functions, covering
  absent-user and explicit-null-vs-absent edge cases specifically).
- `deno check` on `_shared/rank_engine.ts` + `_shared/rank_engine_test.ts` (the CI-covered files): clean.
- `evaluate-rank-promotions/index.ts` carries the same 3 pre-existing type errors as unmodified `main`
  (confirmed via a side-by-side `deno check` diff) — none introduced by this batch; tracked separately
  (spawned task, pre-existing Deno type debt).
- All 5 newly-batched columns confirmed present in `backups/live_schema_columns.json`.
- B-pass: `docs/reviews/opt-e-rank-cron-batch-bpass.md` — accepted, 2 nits folded (cosmetic SoT prose trim;
  a pre-existing unused-column selection noted as out of scope, not introduced here).

**Verdict: converged.** No P0/P1 across 2 rounds + B-pass; all findings folded.
