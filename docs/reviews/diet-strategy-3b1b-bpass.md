---
reviewed_at: 2026-11-15T01:50:00+05:30
staged_against: 72dfbc56 (3b-1b diff b10f6c76..72dfbc56; PR #277, stacked on #275)
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each; plus the round 4 plan confirmation on the same commit)
lens_set: [writer_reader_drift, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 23
verdict: accepted
verdict_note: one P1 (two seats) fixed with a second saved-plan stamp; every P2 fixed except the non-reactive local kill switch, accepted; P3s fixed or accepted with reasons in plan §13
---

# Code Review (B-pass) — diet plan Unit 3b-1b, the Diet Plan screen follows the strategy, shipped dark (`diet-strategy-3b1b`, PR #277) at 72dfbc56

Seats: A writer/reader drift (every reader of the saved plan map, the removed `dietPlanProvider` invalidate, registry ranges); B guards and their mirrors (doors, flag on/off, PRO states, Vegan pairs, fallbacks, timing); C tests passing for the wrong reason. The round 4 reviewer checked the plan against the built code. The coordinator re-checked every finding against the code before acting. Full disposition table: `docs/plans/diet-strategy-3b.md` §13, "3b-1b round 4 and B-pass dispositions".

## P1

### A1 = B1 — writer_reader_drift — a plan saved after a fallback never loads again
- **file:line:** `diet_plan_screen.dart` `_savePlan` (stamp = BUILT strategy) vs `savedPlanMatchesStrategy` callers (`_generatePlan`, `DietPlanNotifier.build`), which compare with the REQUESTED strategy.
- **claim:** with the legacy generator (kill switch) or a missing carb target a Keto request is built Balanced and stamped `balanced`; after Save the provider returns `{}` (no hints) and the next open regenerates and drops it, with no notice.
- **status:** fixed: a second stamp `diet_strategy_requested`; the matcher reads it first; `diet_strategy` stays the BUILT strategy for the swap, the PDF and the note. Test: the kill-switch Keto test saves, reads `dietPlanProvider` (non-empty), re-opens (no new generation, same items). Mutants G1 (matcher ignores the new stamp) and G2 (save omits it): red.

## P2

- **R4-F1 = B3 = C1 — flag-off stamp read:** a stamped plan loaded with the flag off set the swap pool and PDF label to Keto. Fixed (Balanced with the flag off); test: a plan saved as Keto with the flag on and re-opened with it off offers no Low carb only swap, with the precondition that its Keto swaps do. Mutant G3 red.
- **R4-F2 = B2 — the listener before the first plan:** a change between `initState` and the first post-frame generation generated twice and could drop a loaded plan. Fixed: `dietPlanNeedsRegeneration` returns false while `_planEpoch == 0`; pure test; mutant G4 red. The plan's §13 sentence that said this could not happen is corrected.
- **R4-F3 = C3 — the Vegan door:** no screen test of Keto Non-veg -> Vegan -> Non-veg, and the "food-type change does not fire the listener" claim could not fail. Fixed: new test (one generation each way, the vegan line, the disabled Keto chip, both stamps, no grain after the return to Keto); old test renamed.
- **R4-F4 — registry:** the stamp's readers were missing. Fixed: reader `_loadSavedPlan + _swapItem + _sharePlanAsPdf`; ranges recomputed from anchors.
- **C2 — the PDF builder's note:** no pin that `buildDietPlanPdf` passes the note to the header lines. Fixed: presence pin on the call; mutant G5 red.
- **A2 — the local kill switch is not reactive:** accepted: `disable_diet_strategy` takes effect on the next rebuild, as `macroTargetsProvider` already does in 3a.

## P3

- R4-F5 / C6: mutant B17 (restore the `dietPlanProvider` invalidate in `_applyDietStrategy`) run: red, test "a stamped Keto plan loads for a Keto user…".
- R4-F6: the forced fallback is covered by the kill-switch screen test and the pure `noPack` request test; §4 wording means those.
- R4-F7: naming row reworded; §3.6 points at §13.
- A3: three loose `profile_provider.dart` ranges re-anchored.
- A4 / C6: `debugDietPlanGenerations` accepted (an int counter reset per test).
- B4 (Keto + Vegan saved from Edit Profile after a form food-type change), B5 (silent replacement of a same-food-type plan, §3.7), B6 (Edit Profile food-type change while the screen is in the stack, Unit 2a behaviour): accepted.
- C4: B16 recorded (the screen passes `_requestedStrategy` to the swap: red).
- C5: literal carb targets 120 g / 30 g for the fixture.
- C6: a garbage stamp (`paleo`) matches Balanced only, pinned.

## Mutations of the fix commit

`test/nutrition/diet_plan_strategy_screen_test.dart` + `test/nutrition/diet_plan_pdf_test.dart`, each mutation applied once (count checked) and restored: G1 matcher ignores `diet_strategy_requested` (2 red), G2 save omits it (2 red), G3 flag-off load reads the stamp (1 red), G4 regeneration before the first plan (1 red), G5 the builder drops the note (1 red), B17 the invalidate restored (1 red): 6 of 6.

## Founder triage notes

Not needed: no product decision; dispositions above.

## Tuning entry
- **2026-11-15** - blast-radius platform - 23 findings (round 4 + 3 seats, several duplicates); 0 false_alarm; tuning: a stamp that two parties read for DIFFERENT questions (what was it built for vs which request does it answer) needs two fields; two seats found the P1 by naming the writer's quantity and the reader's quantity separately, which no test written from the writer's side could show.
