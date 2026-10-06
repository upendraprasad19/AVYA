---
reviewed_at: 2026-07-08T18:15:00+05:30
staged_against: opt-e-rank-cron-batch (working diff) vs main 237c347
blast_radius: platform
reviewer: fresh-context-blind-sonnet-subagent (5-lens B-pass)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — OPT-E: rank-cron N+1 batch pre-fetch

A fresh, context-blind reviewer ran the 5 canonical B-pass lenses against the diff (`_shared/rank_engine.ts`,
`evaluate-rank-promotions/index.ts`, `_shared/rank_engine_test.ts`, `docs/sot_registry.yaml`) plus targeted
verification of the SoT line-range citation (independently re-derived by reading the file directly, not
trusted from the diff). **Overall verdict: ACCEPTED — no P0/P1.**

## Lens results (all 5 clean)
- **writer_reader_drift** — every field in the 3 batched `.select()` calls (`user_progress`: user_id,
  current_streak_days, deployments_complete, longest_gap_days, last_workout_date; `rank_promotions`: user_id,
  rank_code; `user_profile`: user_id, current_rank_code) confirmed present in `backups/live_schema_columns.json`.
  Map-lookup substitutions (`progressMap.get`, `ranksMap.get`, `currentRankMap.get`) verified to preserve the
  exact same semantics as the old per-user `.maybeSingle()`/`.eq()` calls, including the absent-vs-explicit-null
  distinction for `current_rank_code` (pinned by `rank_engine_test.ts:64-72`).
- **function_exception_swallow** — no `.functions.invoke(` in this diff (server-side Postgres reads only).
  `fetchInChunks` stops and surfaces the error on the first failing chunk (no swallow); the caller aborts the
  whole tick with `logCronEnd(..., "failed")` on any of the 3 batch errors rather than silently continuing.
- **blast_radius_mismatch** — `docs/blast_radius.yaml` names both touched paths (`evaluate-rank-promotions/**`,
  `_shared/**`) as `platform`-tier explicitly (not the wildcard fallback). No schema/RLS/GRANT/auth change
  hiding in the diff (grepped for `policy|RLS|GRANT|REVOKE` — zero hits). `platform` is correct.
- **secrets_in_tree** — zero matches for credential-shaped literals.
- **unawaited_no_error_sink** — zero `unawaited(` calls introduced; both `fetchInChunks` calls inside the
  `Promise.all` are awaited with synchronous error checks immediately after.

## Specifically verified
- **SoT `line_range: 319-340` re-derived independently** by reading `evaluate-rank-promotions/index.ts:319-340`
  directly — confirmed it is exactly the denorm-sync block (reads `current_rank_code` via the Map, resolves
  ordinal via LADDER, conditionally updates only when `winner.ordinal > currentOrdinal`). Not a stale number.
- No debug leftovers (`console.log`/`TODO`/`FIXME`/`debugger`) in the added lines.
- `fetchInChunks` and the 3 Map-builders: no uncaught-exception surface on empty input or chunk-boundary math
  (100/101 users → 1/2 iterations, confirmed).

## Findings (both nits, neither blocks merge)
- **Finding 1 (cosmetic)** — the SoT registry's `notes:` field originally narrated the review's own
  self-correction history (two invalidated line-range attempts before landing on the right one). Trimmed to
  state only the current fact post-review.
- **Finding 2 (pre-existing, out of scope)** — `user_progress.longest_gap_days` is selected but never consumed
  downstream. Confirmed via `git show main:...` this was ALREADY true before this diff (the old per-user query
  selected the same unused column) — not a regression introduced here, not this batch's fix to make.

**Verdict: accepted.**
