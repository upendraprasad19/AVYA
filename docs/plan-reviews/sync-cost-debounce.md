---
branch: sync-cost-debounce
batch: Unit H — offline-first cost optimization (H1a + H3 + H5)
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/sync-cost-debounce-bpass.md
hermes: accepted
hermes_report: docs/audit/2026-06-27-hermes-sync-cost-debounce.md
date: 2026-06-27
---

# Plan-review record — sync-cost-debounce (Unit H)

§4.12 forcing function for the platform-tier sync coalescing change. Reviewed across **4 rounds**,
every claim verified against code by direct Read (`ground_truth_verified: true`).

## The 4 review rounds
1. **Round 1 (pre-impl, ×2 context-blind Opus):** technical-correctness + offline-first-data-loss
   lenses on the design. REJECTED the delta-sync + dirty-schedule ideas (P0 ×2 data-loss — they
   re-tread `feedback_mistake_restore_window` and break the d9b2c5 stale-cloud re-push healer) and
   the skip-restore-on-signup idea (already implemented; widens the e2a4f7 misclassification P0).
2. **Round 2 (pre-impl, on the hardened plan):** corrected the awaited-caller inventory (3rd caller
   `simulation_service:290` found; `logging_type_repair` is actually unawaited) and proved the
   returning-user 96-upsert tax is ONE sweep that debounce can't cut → split to a separate H1b unit.
3. **Round 3 (pre-impl, Opus-4.8 4-lens regression):** "does it break anything else." Surfaced the
   P0 that the trailing pass must be a WHILE-loop (not "exactly one") to avoid dropping a write that
   lands mid-pass; confirmed H3 + H5 regression-safe.
4. **Round 4 (post-impl, B-pass + Hermes on the diff):** B-pass caught a real P1
   (`flushPendingSyncs` started a concurrent fan-out — fixed by routing through the coalescer's
   `trigger`) + a P2 (initTab telemetry — fixed); Hermes (6-lens Opus) verified the coalescer state
   machine, the next-sweep backstop, the EF contract, and H5 → `verdict: accepted`.

## Converged scope (the §4.12 split)
- **SHIPPED — H1a + H3 + H5** (the signup-storm fix): coalesce `syncWorkoutData` / `syncNutritionData`
  (do-while, awaited-caller carve-out to `*Now()`, app-pause flush); `pushSnapshot` → `callFunction`;
  skeleton clears on first Hive frame. All kill-switched.
- **NEXT — H1b** (its own ×2 review): per-schedule-row dirty-filter respecting d9b2c5 +
  `pushSnapshot` debounce with eager-on-identity durability — the returning-user 96-tax.

## Verification
Full suite **3032 green** (exit 0); `flutter analyze` clean (pre-existing infos only); diagnose-doc
`c4f8d2` validated; `sync_coalescer_behavioral_test` pins the no-loss while-loop. Live before/after
`client_errors` call-count re-verify on :8082 is founder-gated.

verdict: converged
