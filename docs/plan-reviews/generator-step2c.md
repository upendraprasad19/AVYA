---
branch: generator-step2c
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step2c-bpass.md
---

# Plan review: generator-step2c (Unit 2C-a, the balanced week at 60+ minutes, OI-475 L2 / L3)

- **Plan:** `docs/plans/2026-11-14-generator-step2c-balanced-week.md` (v6), Part 2C-a (sections 2A, 4A, 5A). Part 2C-b
  (the weekly minimum and the allowance) ships later from its own branch with its own record.
- **Founder basis:** decisions d35-d46 (2026-11-14, step-2 board card t212): the balanced 3 / 4 / 5-day build_muscle
  splits at 60+ minutes (d35, d39, d40, d41, d43), the credit rule (d35), rule-14 waivers for `plan_generator.dart`
  lines 169 and 288 (d36, d40), one kill switch (d37), the 3-day Full Body day varies from Upper and Lower (d46).
- **Tier and blast radius:** tier L (plan engine), blast radius platform.
- **§4.6:** one Hive kill switch, `disable_balanced_week` (`PlanEngineFlags.balancedWeekEnabled`, ON by default after
  the full review), read by each callee (`selectV4`, `quadPrimaryCreditsGlutes`, the repeat-pin row check). Switched off, the
  generator reproduces main c6b1ee48 byte for byte over the 1,010 golden personas (fixture
  `generator_golden_hashes_balanced_week_off.json`); nothing new is written to Hive.

## Review rounds

Four rounds of fresh, context-blind Sonnet seats (read-only; no tests run), each verifying claims against main's code
and the prototype dumps (2,304-plan audit).

- **Round 1 (v1, two seats): not converged.** P0: the new days had no B lists (weeks 2 / 4 repeated weeks 1 / 3). P1s:
  same-type repeats, the count max, the 6-day precedence, the test oracles, missing reds. Founder questions followed
  (d38-d43).
- **Round 2 (v2, two seats): not converged.** P1s: the same-type avoid never reached the picker
  (`VolumeFilter.filterDays` dropped the field), the minimum's reorder misaligned copied days, the allowance cost the
  lead a set, extra `plan_generator.dart` lines for the switch, the minimum zeroed groups. Founder: d44, d45. The unit
  was split (§4.12.1): 2C-a first.
- **Round 3 (v3, two seats, scope 2C-a): not converged.** P1s: the day-name pin guard had no data (replaced by the
  `balanced_week` marker and the G5 gate), §4A had been scored with today's credit (re-measured on one audit rule: 0
  regressed, 98 improved), hand-picked red lists (every caller is run). Founder: d46.
- **Round 4 (v4, one seat, scope 2C-a): converged.** Every recomputed number matched (verdicts, issue deltas, scope,
  Quads cells, repeats). Findings were specification completeness only (the pin tests in the caller list, the marker's
  plumbing and the reschedule re-stamp, "OFF writes nothing new", the 60-minute Quads table); all folded into v5. No
  design finding.
- **Build-time change (v6):** the repeat-pin protection moved from a stored marker (v5) to a check of the rows the pins
  come from (a mid-phase reschedule makes a stored marker stale for weeks 1-2). Narrower than v5 (no new Hive write);
  the B-pass seat reviews it on the code.
- **Build-time notes (plan §6).**
  - The test oracles restate the credit rule instead of calling the predicate. This reverses round 1's A-5: an
    oracle that calls the helper cannot catch a wrong helper.
  - The gate matched §4A.2 on its first run.
  - The golden is re-recorded with per-class attribution (diagnose `c7e5a1`).
  - The day-floor gate's floor-off thin tallies moved. The balanced 5-day's Push, Pull and Upper days are the
    default 5-day's, and the floor seats every one of those thin days.

## Ground truth

- Prototypes restored with sha checks after every run; measurements in the session scratchpad (`step2c/audit_base2`,
  `audit_va2fb`).
- 2C-a against today on one audit rule: suitable 788 -> 886, 0 regressed, 98 improved; build_muscle Quads cells under
  the band bottom at 60 / 90 minutes 384 / 336 -> 296 / 120; every 30 / 45-minute plan, every other goal and every 6-day
  plan byte-identical.
