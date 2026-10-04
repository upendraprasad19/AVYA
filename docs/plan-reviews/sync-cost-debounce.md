---
branch: sync-cost-debounce
batch: Unit H (H1a/H3/H5) + H1b (Part A schedule dirty-filter + Part B1 pushSnapshot debounce) — offline-first cost optimization
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/sync-cost-debounce-h1b-bpass.md
hermes: accepted
hermes_report: docs/audit/2026-06-28-hermes-h1b-sync-cost.md
date: 2026-06-28
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

## H1b — the returning-user tax (rounds 5–6)

5. **Round 5 (pre-impl foolproof, founder-directed):** 4 Opus explorers → design → 5 adversarial
   lenses → synthesis, every claim re-verified against source. Caught the load-bearing P0 (a naive
   dirty-filter would skip stale-cloud `completed` rows → cross-device completion loss → A-fix-1
   never-skip-completed) and the biggest residual risk (the cross-account `coach_memory` leak →
   B-fix-1). Verdict: SHIP Part A (4 fixes) + Part B1 (3 fixes); DROP Part B2; TWO commits, A first.
6. **Round 6 (post-impl, B-pass + 4-lens Hermes on `36495ba..HEAD`):** B-pass caught a P1
   test-coverage gap (no Hive round-trip for the fingerprint index → added) + 5 false-alarms; Hermes
   concurrency lens caught the **real P1** the design's own GATING claim missed — an ALREADY-IN-FLIGHT
   `pushSnapshotNow` parked on its EF await across an A→B swap mirrors A's response coach_memory into
   B's coachBox (B-fix-1's coalescer reset only drops an OWED pass). FIXED → **B-fix-4** (sync
   `currentUser?.id == userId` re-check before the mirror, atomic with the box resolution) +
   jsonEncode fingerprint hardening + 2 doc-accuracy P2s. All resolved in-batch (no deferrals);
   `verdict: accepted` on both `docs/reviews/sync-cost-debounce-h1b-bpass.md` +
   `docs/audit/2026-06-28-hermes-h1b-sync-cost.md`.

**H1b shipped:** Part A `edcb4f5` (schedule dirty-filter, diagnose `b4f7e2`) + Part B1 `e46a1bc`
(pushSnapshot debounce + cross-account guard, diagnose `e7c1a9`) + the review-fixes commit. Each
kill-switched; full suite green; gates green. The Unit-H review files remain at
`docs/reviews/sync-cost-debounce-bpass.md` + `docs/audit/2026-06-27-hermes-sync-cost-debounce.md`.
Live before/after call-count re-verify on :8082 + the `--no-ff` merge are founder-gated.

verdict: converged
