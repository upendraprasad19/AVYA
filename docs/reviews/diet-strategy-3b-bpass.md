---
reviewed_at: 2026-11-14T23:55:00+05:30
staged_against: ea5d8146 (committed diff 21db03c7..ea5d8146, CI green on the head; PR #275)
blast_radius: account
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each; plus the round 4 plan confirmation on the same commit)
lens_set: [writer_reader_drift, missing_input, guard_without_its_mirror, asserted_fixture_value, blast_radius_mismatch]
findings_count: 21
verdict: accepted
verdict_note: no P0 or P1; every P2 fixed in the follow-up commit; four P3s accepted as stated limits (plan §12 rows 11-13), the rest fixed
---

# Code Review (B-pass) — diet plan Unit 3b-1a, Low carb / Keto catalog, generator and swap, shipped dark (`diet-strategy-3b`, PR #275) at ea5d8146

Three seats, each context-blind, each with its own lenses:
- seat A: writer/reader drift (every reader of the catalog, `is_everyday`, the food rows, `DietPlanInputs`; the inserted-lines sub-check on `docs/sot_registry.yaml`);
- seat B: guards and their mirrors (generator vs swap, Low carb vs Keto, stale boxes), missing input (counted in the real asset);
- seat C: tests that pass for the wrong reason (circular expectations, vacuous loops, unpinned constants, golden provenance).

A fourth context-blind reviewer ran the round 4 plan confirmation on the same commit; its findings are folded in (R4). The coordinator re-checked every finding against the code before acting. The full table of dispositions is in `docs/plans/diet-strategy-3b.md` §12.

## Seat A — writer/reader

### A1 — P2 — writer_reader_drift (inserted lines)
- **file:line:** `docs/sot_registry.yaml` `passesDiet` entry, `line_range: 1328-1365`
- **claim:** 11 lines were inserted above `passesDiet` in `diet_plan_generator.dart`; the range is stale.
- **status:** fixed (`1339-1376`, the signature and closing brace re-read).

### A2 — P2 — writer_reader_drift (inserted lines)
- **file:line:** `docs/sot_registry.yaml` seed-service prune entry, `line_range: 282-327`
- **claim:** 7 lines were inserted above the block in `seed_service.dart`.
- **status:** fixed (`289-334`; base line 282 and new line 289 hold the same text, likewise 327 and 334).

### A3 — P3 — writer_reader_drift
- **file:line:** `diet_plan_catalog.dart` `dietCatalogFamily` read by `diet_plan_provider.dart` `savedPlanMatchesFoodType`
- **claim:** fried egg / cheese omelette now carry the egg family; a legacy plan holding them loads for an eggetarian or pescatarian.
- **status:** kept as correct and tested (same as R4 F1).

### A4 — P3 — dual-role resolution of a loaded plan (coconut)
- **status:** accepted (plan §12 row 13).

### A5 — P3 — wording ("151 foods", registry v4 sentence)
- **status:** fixed.

## Seat B — guards and mirrors, missing input

### B1 — P2 — guard_without_its_mirror
- **file:line:** `curated_diet_plan_generator.dart` `_normalised` vs `diet_plan_swap.dart` `swapAlternatives`
- **claim:** the swap does not repeat the generator's normalisation, so a caller passing the requested strategy gets Keto rules on a plan built Balanced.
- **status:** fixed as a contract on `swapAlternatives` (pass `builtFor` / the saved stamp); 3b-1b passes `_planStrategy` and tests it.

### B2 — P3 — a swapped item at a larger portion can exceed the Keto item cap
- **status:** accepted and stated on `swapAlternatives` (the generator's cap is also at the smallest portion).

### B3 — P3 — a failed v5 re-seed leaves the swap and the generator disagreeing for a launch
- **status:** accepted (self-healing on the next launch).

### B4 — P3 — misplaced doc comment on `dietFamilyDailyCap`
- **status:** fixed.

### B5 — P3 — same as A3
- **status:** see A3.

## Seat C — tests

### C1 — P2 — no calorie ceiling, no fiber observer
- **status:** fixed: per-strategy kcal ceiling, per-plan carb ceiling and fiber floor, measured on the built code (kcal max 1.10, carbs max 1.47 / 1.30, fiber min 0.33 / 0.13) with a small margin.

### C2 — P2 — the carb bound is one mean
- **status:** fixed (per-plan ceiling, C1).

### C3 — P2 — the template test reads the table it checks
- **status:** fixed: literal template table for Keto and Low carb; shares sum to 1 for every strategy.

### C4 — P2 — the cap test reads the override it checks; the override is never shown to be used
- **status:** fixed: literal override map and `kKetoItemCarbCap == 6`; a test that some plan goes past a Balanced cap (measured: paneer, soy, dairy, fat); vegan Keto plans judged by the Balanced caps.

### C5 — P2 — vacuous swap assertions
- **status:** fixed: Keto alternatives non-empty and an over-cap entry exists for a swapped role; a Low carb swap case; the Balanced role check compares every Low carb only id with an id outside the catalog in three slots, and Keto resolves ghee to `fat`.

### C6 — P2 — hand-copied 14-id sets
- **status:** fixed: both sets asserted equal to the catalog's `lowCarbOnly` ids.

### C7 — P3 — `built` collected, never asserted
- **status:** fixed (per-plan `builtFor`).

### C8 — P3 — golden provenance
- **status:** recorded: the G1/G2 bodies were run on a detached `origin/main` `21db03c7` worktree before the catalog append; the main signatures hash to the two constants (`96f7e27c…`, `0acb6a7d…`).

## Round 4 (plan confirmation) — folded in

- R4 F1 (P2) = A3: tested and the plan / record / CLAUDE.md say it.
- R4 F2 (P2) = C4.
- R4 F3 (P2): the mutants "carb term off in `_dayScore`" (A6) and "keto fiber aim 0.8" (A7) were run on the built code: both red (A6: 1 test, A7: 1 test). Mutants A1–A16: 15 red, A4 (fat exemption) survived and the exemption was removed.
- R4 F4, F5, F6 (P3): numbers fixed; dual-role accepted; provenance recorded (C8).

## Mutations of the new pins (follow-up commit)

Each new pin was mutated once on the fixed tests (`test/nutrition/curated_diet_plan_strategy_test.dart`, 20 tests), the mutation confirmed applied (count 1) and restored:

- F1, the Keto dairy override 3 -> 2: red (2 tests).
- F2, a grain added to the Low carb dinner template: red (3 tests).
- F3, `resolveSwapRole` skips the Balanced `lowCarbOnly` filter: SURVIVED on the first run. Every Low carb only id's real category happens to map to the role its catalog entry gives, so "resolves like an id outside the catalog" held by coincidence. The test now also resolves every Low carb only id with no category (Balanced: null in all three slots; Low carb: the fried egg resolves to `breakfastProtein`). Re-run: red (1 test).
- F4, the generator ignores `dietFamilyLowCarbCapOverride`: red (2 tests).

## Founder triage notes

Not needed: no P0/P1, no product decision; dispositions above.

## Tuning entry
- **2026-11-14** - blast-radius account - 20 findings (incl. round 4) plus 1 surviving mutant of the fix's own pins; 0 false_alarm; tuning: a test whose bound is computed from the constant under test cannot see that constant change; pin the constant literally and add a "the raised cap is actually reached" observer (seat C finding 4, round 4 finding 2). A "resolves like an outsider" comparison can hold by data coincidence (F3): also compare with the fallback input removed.
