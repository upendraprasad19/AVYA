---
adr_id: 0011
title: Sequential (no-skip) rank progression with deployment-per-phase
status: accepted
date: 2026-05-31
deciders: Upendra
---

# ADR-0011: Sequential (no-skip) rank progression with deployment-per-phase

## Context

ICANBEFITTER's rank ladder (`rank_ladder_data.dart` + `_shared/rank_engine.ts`)
is an 11-rung Indian-Navy metaphor: SD2 → SD1 → LS → PO → CPO → MCPO → SubLt →
Lt → LtCdr → Cdr → Capt. Gates mix streak, calendar tenure, completion rate, and
a `deployments_complete` counter (PO needs ≥2, CPO ≥3).

A year-simulation surfaced three coupled problems:

1. **`deployments_complete` was never written** (an F18 deferral). The client
   read `progress['deployments_complete']` which stayed 0, so PO/CPO were
   permanently unreachable.
2. **Both engines "leap-frogged"** — `_qualifiedRankCode` /
   `highestQualified` picked the highest *independently*-qualifying rung. An
   officer-track completion-rate qualifier could skip the locked PO/CPO rungs.
3. **The server cron read four `user_progress` columns that did not exist**, so
   it was silently inert (diagnose b9f4d2).

The founder's intent: completing a training phase should *earn* something toward
rank, and **ranks must not be jumped** — you earn each rung in order.

## Decision

**A deployment = a completed phase, and rank advances strictly sequentially.**

- `deployments_complete = current_phase - 1`, stamped monotonically in
  `UserRepository.saveProgress` (the single progress writer every phase-advance
  path funnels through) and synced to `user_progress.deployments_complete`.
- Both engines evaluate the ladder as a **contiguous walk**: start at SD2,
  advance to the next rung only while its gate passes, **stop at the first failed
  gate**. The deployment-gated PO/CPO cannot be skipped — reaching any officer
  rank requires having earned PO + CPO first.
- Monotonic no-demotion (`shouldPromote`) is preserved: rank is a peak.
- Client (`rank_service._qualifiedRankCode`) and server
  (`rank_engine.highestQualified`) stay in lockstep.

## Alternatives considered

1. **Keep "highest independently-qualifying rung" (leap-frog).** Rejected — the
   founder explicitly wants no skipping; leap-frog made PO/CPO cosmetic and the
   metaphor incoherent (you could be a Lieutenant without ever being a Petty
   Officer).
2. **Derive deployments server-side as `current_phase - 1` only (no column).**
   Rejected as the sole fix — the cron also needs streak/gap, and the client
   rank engine (the primary promoter) reads from Hive; a synced column keeps both
   sides consistent and lets `getPromotionStatus` agree.
3. **Recompute the schedule-aware streak server-side.** Rejected — re-implementing
   the freeze-aware streak walk on the server is the recurring writer/reader-drift
   bug source. The client is the source of truth; we sync its computed values.
4. **Count a deployment only for post-phase-12 "deployment cycles."** Rejected —
   that would leave PO (week-12 gate) unreachable until ~week 48. Counting every
   completed phase (incl. 1-12) aligns the deployment count with the existing
   `current_phase - 1` server derivation and the gate timing.

## Consequences

Good:
- The rank metaphor is coherent and the full ladder is reachable: completing
  phases earns deployments → PO/CPO → (with tenure + completion rate) the officer
  track up to Lieutenant (~130 weeks) and beyond.
- One monotonic writer; client + server agree; the previously-inert cron works.

Bad / watch:
- **Steep mid-ladder wall:** the no-skip rule means CPO's `streak ≥ 50` is a hard
  gate to *any* officer rank. Realistic ~85%-adherence users who never sustain a
  50-streak will stall at the sailor track — accepted as the intended challenge
  (gates left as-is this batch).
- **Lockstep burden:** any future gate or ladder change must edit BOTH
  `rank_ladder_data.dart` and `_shared/rank_engine.ts` and re-run the parity test.
- **Reaching Lt is a ~2.5-year journey** — only demonstrable via the simulation
  harness, not a quick manual test.

## Status

Active. Shipped 2026-05-31 with migration 081 + `evaluate-rank-promotions`
redeploy. Diagnose b9f4d2. Account/platform blast radius.

## See also

- `docs/diagnoses/2026-05-31-rank-cron-nonexistent-columns-b9f4d2.md`
- `lib/core/services/rank_ladder_data.dart` + `supabase/functions/_shared/rank_engine.ts`
- `lib/core/services/rank_service.dart` (`_qualifiedRankCode`, `shouldPromote`)
- `supabase/migrations/081_user_progress_rank_eval_columns.sql`
- `docs/architecture/functionality-flow.md` (TRAIN rank/deployment assertions)
- ADR-0009 (plan generator) — post-phase-12 deployment cycles feed the counter
