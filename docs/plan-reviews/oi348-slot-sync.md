---
branch: oi348-slot-sync
date: 2026-11-23
blast_radius: platform
review_rounds: 16
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — OI-348 Landing 1a-ii (nutrition slot sync: every device converges on the same meals; closes OI-281)

Plan: `docs/plans/nutrition-slot-sync.md`, FINAL v17 (one consolidated spec; its Appendix A records every round). Founder decision 2026-11-22: "We will build it properly, we will build B. No shortcuts."

## Rounds (context-blind Sonnet reviewers; each verified the plan's claims against the code, and live data where needed)

- Rounds 1-7 (v1-v7, layered amendments): `not_converged` each, 1-4 P1 per round, all in identity and in reconciling pre-build history. Round 3 split the landing per §4.12.1: Landing 1a-i (the doubling hotfix) shipped first (PR 327, merged 2026-11-23); this is 1a-ii.
- Round 7 asked for one consolidated text: v8 is a full rewrite, not an amendment.
- Rounds 8-14 (v8-v14): `not_converged`, 1-2 P1 each, every one in the same place: legacy (old-format) cloud rows met after a device's re-baseline (kill switch, old clients). Round 13 led to REMOVING that class (§4.12.1, shrink the unit): a legacy write seen after a re-baseline now triggers a FULL re-baseline instead of a merge rule; round 14's P1 (a missed legacy write under a newer row) was closed by a server `legacy_rev`.
- **Round 15 (v15): `converged`** (0 P0/P1; 5 P2 applied in v16).
- **Round 16 (v16, the confirming round on the post-review text, §4.12.1): `converged`** (0 P0/P1; 2 P2 + 3 P3 applied in v17 as wording and one shared admission predicate, no design change).

## Ground truth verified
Every round read the cited code (`nutrition_write_service.dart`, `sync_nutrition.dart`, `sync_service.dart`, `sync_skip_index.dart`, `serial_slot.dart`, `sync_retry_controller.dart`, the 17 whole-box readers, the migrations' DDL). Live (project `dedsavbjuwgarrhphgnl`, read-only): `nutrition_logs` columns (no items/source, 2026-11-22) and its `meal_type` values (92 rows, breakfast/lunch/dinner/snacks only, no null, 2026-11-23).

## Execution
Inline, one worktree (`oi348-slot-sync`), decided at start (§4.12.7). The migration's live apply needs the founder's explicit go (§4.3).

## B-pass
Pending (self-initiated before the merge, §4.3).
