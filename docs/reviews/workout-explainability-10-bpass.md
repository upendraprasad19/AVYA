---
review: B-pass (context-blind, adversarial)
branch: workout-explainability-10
scope: Batch 10 · W3.1 explainability — deload "why" (arc strip) + adherence "why" (non-shaming copy)
blast_radius: account
verdict: accepted
---

# B-pass — Batch 10 (W3.1 explainability)

Self-initiated ≥account B-pass (§4.3) on the implemented, staged diff BEFORE the `--no-ff` merge.
A context-blind adversarial reviewer verified 8 bug classes against the actual code, ran
`flutter analyze` (7 items, clean) and the tests (49 passed).

## Verdict: accepted — no P0, no P1, no P2.

## Bug classes hunted → all CLEAN (reviewer verified against code)
1. **Deload behavior byte-identical (P0)** — the `if(shouldLift){…return;}` → `if/else` restructure is
   behaviorally identical (flag/marker/lift writes unchanged; the KEEP block moved verbatim into the
   `else`, only reachable when `!shouldLift`). `_liftWeekFour` returns `true` on every lift path
   (`:260`) and `false` on the no-eligible-row early return (`:221`); side-effects unchanged. The
   reason `box.put` is purely ADDITIVE, runs after the flag/marker writes, and `maybeEvaluate` is
   try/caught + `recordNonFatal` by `day_rollover_service.dart:180-186`.
2. **Writer==reader phase (P1)** — eval's `sched.getWeek(4)` and reader's `getWeek(4)` both resolve to
   `WorkoutScheduleReadService.getWeek(4)`, both derive P via the shared `deloadPhaseFromWeek4` →
   writer==reader; `plan_start_date` advances per phase so the [1,4] clamp is accurate (reason renders
   only on the real deload week).
3. **Inertness (P0)** — `reason==null` → the collection-`if` adds nothing → Column byte-identical to
   7-A; not-week-4 short-circuits the ternary (never watches the provider); flag-off reader → null;
   adherence flag-off → sheet unreachable.
4. **Outcome-match / R2-1 fix (P1)** — `shouldLift && !liftedAny` → "Recovery week logged…", explicitly
   NOT "Working week"; `_liftWeekFour` returns false before the blob dual-write so the week stays
   `deload` and the copy matches the DELOAD node the strip shows.
5. **Reader crash-safe + flag-gated (P1)** — `currentDeloadReason` is try/caught, checks
   `triggeredDeloadEnabled` BEFORE the Hive read (`:724-725`); imports present (`PlanEngineFlags` :34,
   `HiveService` :22).
6. **Adherence copy (P2)** — sheet signature unchanged; copy is a non-shaming lead-in, no %/"failed"/
   "missed", consistent with the file's own brand contract (`:1-4`).
7. **Round-trip validity (P1)** — the new group drives the REAL `maybeEvaluate()` → REAL
   `currentDeloadReason()` and asserts they agree (`:603,:636`) — genuine round-trip, not hard-coded.
8. **Other (P0/P1)** — `deload_reason_phase_*` is LOCAL-only (sync sweeps only `exlog_`/`schedule_`
   prefixes → no cross-account leak, matching the existing marker/flag keys); SoT entry accurate;
   no null-safety gaps.

Non-blocking observation (not a finding): the flag-off eval tests don't assert the reason key is
absent, but flag-off returns before any write + the reader-gate test covers flag-off→null, so
correctness is fully pinned.
