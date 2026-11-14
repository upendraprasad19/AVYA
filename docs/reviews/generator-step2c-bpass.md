---
reviewed_at: 2026-11-14T17:30:00+05:30
staged_against: dbbda4cf48531137dcf2ed878c99a44cea363e5d
branch: generator-step2c
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 4 P2 and 3 P3, all fixed or stated in the review commit
---

# B-pass: generator-step2c (Unit 2C-a, the balanced build_muscle week at 60+ minutes, OI-475 L2 / L3)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head dbbda4cf with CI green on that SHA
(`land_pr.sh 272 --ci-only`, `result: ci-green`). Two fresh Sonnet seats reviewed the three-dot diff
`origin/main...HEAD`:
- **Seat 1, the engine:** split_resolver, models, volume_filter, exercise_selector, flags, plan_generator lines 169 /
  288. Lenses 1, 3, 6 and 7, with mutation allowed.
- **Seat 2, the repeat pins and every test file:** lenses 1, 6 and 8, read only, since seat 1 was mutating the same
  tree.

Both briefs quoted the recorded decisions:
- d40 / d43: only 60+ minutes;
- d35 / d36: build_muscle only, and the line 169 / 288 waivers;
- d46;
- the rejected stored marker;
- 2C-b is out of scope;
- oracles restate the rule.

## Finding S1-1 — P2 — writer_reader_drift (inserted-lines sub-check)
- **file:line:** docs/sot_registry.yaml (the `isRestDayConsideringLogged` reader of `plan_engine_flags.dart`)
- **claim:** The range was shifted 513-518 -> 528-533, but the function sat at 530-535. The flags file was edited
  (2 lines) after the shift was computed.
- **verification:** `grep -n isRestDayConsideringLogged` on origin/main (513) and HEAD (530).
- **status:** accepted, fixed. The review commit also removes a blank line in that file, so the range is now 529-534,
  checked against the file. Every range in the two files edited after the commit was re-derived from a HEAD-to-tree
  line map; one result had already been hand-corrected, and was set back by reading the file.

## Finding S1-2 / S2-3 — P2 — guard_without_its_mirror (kill switch scope)
- **file:line:** lib/core/services/workout_schedule_read_service.dart (`repeatPinsFrom`, the `workout_day_index >=
  daysPerWeek` refusal)
- **claim:** The day-index refusal is not behind `disable_balanced_week`, so "OFF equals main" is too wide for repeat
  pins.
- **verification:** read of the diff; only `foreignDayNames` depends on the switch.
- **status:** accepted. It is a deliberate defect fix (diagnose c7e5a1, plan "the days case"). The plan, nested
  CLAUDE.md, registry and OI-509 now say the refusal is outside the switch and stays when the switch is deleted.

## Finding S2-1 — P2 — test gap (the auto path's minutes)
- **file:line:** workout_schedule_read_service.dart, `autoGenerateNextPhaseIfNeeded`'s `_buildRepeatPins(sessionDuration:)`
- **claim:** Only the graduation entry point (`buildRepeatPinsForAdvance`) was tested. Dropping the argument on the auto
  path would make the pins resolve the profile's minutes while the generate uses the param, and no test went red.
- **status:** accepted, fixed. `test/contracts/repeat_content_scheduling_test.dart` gains "a 45-minute phase advanced at
  45 / 60 minutes" through `WorkoutScheduleService.autoGenerateNextPhaseIfNeeded`. The prior phase holds today's
  family: at 45 it repeats, at 60 it refuses. The mutant (the argument removed; anchor gone, count 0) turns exactly the
  45-minute case red.

## Finding S2-2 — P2 — writer_reader_drift (template day names)
- **file:line:** workout_schedule_read_service.dart (`foreignDayNames.contains(row['workout_name'])`). Writer:
  lib/features/ai_coach/services/schedule_template_planner.dart (free-text day names).
- **claim:** The comment said the foreign names are names only the generator writes. A template or coach day named
  `Push` or `Chest` is a row of the new phase whose name is in the foreign set, so it refuses the pins.
- **status:** accepted as stated behaviour. It only over-refuses: the advance fresh-fills and never pins a wrong frame.
  Aligning by index (the seat's alternative) still refuses a `Push` template at index 0, so it adds code without
  closing the case. The comment, plan, glossary, nested CLAUDE.md and registry now describe it.

## Finding S1-3 — P3 — missing_input (the thin-day top-up)
- **file:line:** lib/shared/repositories/plan_engine/exercise_selector.dart (`topUpDays` soft-avoid set)
- **claim:** An injured user's thin-day top-up gets no earlier-day names, so a topped-up Upper B can repeat Upper A.
- **status:** accepted as stated behaviour, the same as OI-458's feeder names, which the top-up never received either.
  Stated in the diagnose doc.

## Finding S2-4 — P3 — wording
- **file:line:** `foreignDayNamesFor`'s doc comment ("empty when the two families are the same")
- **status:** accepted, fixed: the comment states the 5-day `Legs` overlap (an old 5-day week also holds `Chest`).

## Finding S1-4 — P3 — wording
- A double blank line after `balancedWeekEnabled` in plan_engine_flags.dart. **status:** accepted, fixed.

## Checked clean (seat reports, condensed)
- **Every `MuscleSlotDay(` construction in lib** is split_resolver, volume_filter (which carries the field) or the
  constructor. The allocator and the selector build `PopulatedDay`, so nothing else can drop `avoidEarlier`.
- **Minutes.** `generateV4`'s `selectV4` call and its credit both resolve `resolveMinutes(param, profile)`, so the split
  and the credit cannot disagree. Out-of-range and null values land on 60 in both. The pin builder resolves the same
  expression with the same argument on both paths.
- **Switch set.** `quadPrimaryCreditsGlutes` reduces to main's `!(quadLegsB && hasQuadLegsBSplit)`; `selectV4` returns
  main's lists.
- **Selector.** Earlier names are lowercased on write and on read, and same-movement partners are expanded; `all`
  never self-avoids. Seat 1's mutant (B filled from A's picks) was red in the behavioral test, and the file was
  restored with a sha check.
- **Lists** against plan §2A: Core 3rd on Lower and 4th on Full Body; arms within the first five Upper slots; the 5-day
  Upper led by Mid Chest; no leg slot on Push (d39).
- **Recomputed literals.** The foreign-name sets (3 / 4 / 5-day), the balanced day names and the 5-day expectation all
  match the source.
- **Test discipline.** The oracles restate the rule. Only the audit dump (by design) and the S5 per-reader consistency
  test call the predicate.

## Founder triage notes
Self-triaged under the standing directive (carry a unit through its pipeline). No finding re-opens a founder decision.

## Tuning entry

- **2026-11-14** - blast-radius platform - 7 findings (0 P0/P1, 4 P2, 3 P3); 0 false_alarm; tuning: a registry
  range shift computed before a later edit of the same file goes stale. Re-derive every range from a line map AFTER
  the last edit, and re-check by hand any range already hand-corrected (the map double-shifted one here). When two
  seats share a worktree, only one may mutate.
