---
reviewed_at: 2026-11-13T15:30:00+05:30
staged_against: e2486ce807162af083c70d41c4b9af60e800d82c
branch: generator-step2-allocator
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 14
verdict: accepted
verdict_note: no P0 or P1; every P2 and P3 fixed in the review commit or verified clean with evidence (below)
---

# B-pass: generator-step2-allocator (Unit 2A, the lead-first set allocator, OI-486)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head e2486ce8, with CI green on that SHA
(`land_pr.sh 261 --ci-only`, `result: ci-green`). Three fresh Sonnet seats reviewed the three-dot diff
`origin/main...HEAD`. Each brief:
- carried the plan's founder decisions (d26-d29), its rejected alternatives and its out-of-scope list, quoted;
- gave an exhaustive command list (read-only git, file reads, `dart analyze`, named `flutter test` files);
- banned `dart run scripts/*`, `scripts/*.sh`, network tools and every database statement.

The seats:
- Seat 1: the allocator and week-2 logic. Lenses 1 and 3, lens 6 by reading, and plan conformance.
- Seat 2: tests, re-recorded pins and docs. Lenses 8, 1 (inserted lines) and 7.
- Seat 3: mutation. Lens 6 by mutating the four lib files under a backup / restore / sha256 protocol.

Result: 0 P0, 0 P1, 3 P2, 11 P3. All are closed below, together with the fixes in the review commit.

## Seat 1: allocator logic (0 P0-P2, 3 P3)

### Finding S1-1: P3, writer_reader_drift
- **Verdict:** verified_clean.
- **file:line:** `periodization_engine.dart:187` vs `session_set_allocator.dart:332` (`_groupsOf`).
- **claim:** Week 2 reads `ex.primaryMuscles ?? []`, while the allocator falls back to the library row. A budgeted row
  with null muscles would be focus-exempt in week 1 and capped in week 2.
- **Evidence:** every budgeted row is built by `exercise_selector.dart:876`, which sets `primaryMuscles: muscles`, a
  non-null list taken from the row itself. Only the custom builder (`:757`) can set null, and customs are never
  budgeted. The selector builds `PlannedExercise` in exactly these two places (`check_exercise_seams.dart` counts
  them). Both weeks therefore read the same groups.

### Finding S1-2: P3, writer_reader_drift
- **Verdict:** fixed.
- **claim:** B's `leadSeats` had no entry for a day copied from A, so B's list did not cover B's week.
- **Fix:** the copy block now adds A's entries for the copied days, as it does for `countForced` and `belowCount`. The
  list is sorted by day, and the field doc says so.
- **Tests:**
  - "A keeps the capped world" asserts `statsB().leadSeats == statsA().leadSeats` and days `[0, 1]`.
  - "B keeps the lead world" swaps the days, so a copied day follows an allocated one, and asserts day order.
- **Mutants:** removing the copy reddens 1 test, and removing the sort reddens 1 test.

### Finding S1-3: P3, guard_without_its_mirror
- **Verdict:** verified_clean.
- **claim:** the kill switch is read twice per generation.
- **Evidence:** `allocate` (`plan_generator.dart:293`) and `apply` (`:301`) run synchronously back to back, with no
  `await` between them. A Hive `put` from elsewhere cannot interleave in one isolate, so the two reads always agree.

### Observation: one failed run
- **What happened:** one run of the two allocator test files showed `+74 -1`, and it did not reproduce.
- **Cause:** seat 3 was applying mutants to the same worktree at the same time. That is an orchestration error, logged
  in the Tuning entry.
- **Evidence:** on the clean tree, three consecutive runs of the same two files gave `+75` each.

## Seat 2: tests, pins and docs (0 P0-P1, 2 P2, 4 P3)

### Finding S2-1: P2, asserted_fixture_value
- **Verdict:** fixed (traced).
- **claim:** the v14 positive-control pin moved from the 3-day to the 4-day full_gym / advanced plan with "cause not
  traced".
- **Trace (probe, switch set vs unset):**
  - The 3-day plan's Legs day holds five Glutes-crediting rows. At 2 sets each they fill the advanced build_muscle
    Glutes session cap of 10.
  - R1 seats the lead, Barbell Back Squat, at 3. Hip Abduction Machine would make 11, so the cap refuses it.
  - The eighth seat goes to Hanging Leg Raise (Core). This is the plan's D-2A-2 swap class.
- **Recorded in:** the test comment and the diagnose doc. The probe file was deleted.

### Finding S2-2: P2, asserted_fixture_value
- **Verdict:** fixed.
- **claim:** "the lead seated at 3 counts once against the day's target" passed with the rule off.
- **Fix:** the test now also asserts `leadWorld == 'lead'` and the lead's `leadSeats` entry, so it fails with the rule
  off.

### Finding S2-3: P3, asserted_fixture_value
- **Verdict:** fixed.
- **claim:** the count-forced excuse (up to 300 s) is permanent in four sweeps, so a new forced day or a deeper overrun
  would stay green.
- **Fix:** each sweep now pins the exact map of excused days and their overrun seconds.

  | Sweep | Excused days | Overrun |
  |---|---|---|
  | Allocator seeded sweep | 25 variant-days in 12 seed plans | 10.8 to 198 s |
  | Consumers | 15 day-weeks of seed plans 16, 54, 55 and 57 | 10.8 to 90 s |
  | Wiring | 8 day-weeks | 10.8 to 75.6 s |
  | oi489 | Lower Body in weeks 1-3, both goals | 32.9 minutes |

- **What it uncovered:** three comments understated the counts, and the diagnose doc too:
  - "seed plan 16's day 0" (consumers);
  - "one day here is 39.6 s" (wiring);
  - "week 1's Lower Body" (oi489).

  All are corrected. Every measured overrun is inside the 300 s bound that d26 and d28 accepted.

### Finding S2-4: P3, kThinCeilings raised
- **Verdict:** verified_clean.
- **Evidence:** the cause is measured. A pinned repeat starts from a 2A phase 1, and a day holding one exercise fewer is
  d26's accepted cost. The plan, the closure ledger and OI-452 (the input to unit 2B) record it, and the PR description
  names it.

### Finding S2-5: P3, same-movement floor 931 -> 719
- **Verdict:** fixed (recorded).
- **Fix:** N16 Dumbbell Walking Lunge falling 8 -> 0 and N19 falling 633 -> 379 are noted on OI-475 as the input to
  unit 2C (weekly minimums).

### Finding S2-6: P3, stale line reference
- **Verdict:** fixed.
- **Fix:** the plan's `expectNoThin` reference now reads `:361-371`.

### Not counted: the commit trailer remark
- **Verdict:** false_alarm.
- **Evidence:** the commit's Co-Authored-By line matches the session's attribution instruction.

## Seat 3: mutation (22 mutants, 18 red, 4 green)

### Finding S3-1 (M16): P2, guard_without_its_mirror
- **Verdict:** fixed.
- **claim:** the whole-plan fallback could read B from main's A (`bOut = aM.out`) without any test failing.
- **Fix:** the "neither B world holds" test now asserts day 1's B names (`ham`, not `calf`) and B equal to the
  switch-off run.
- **Mutant:** reddens 1 test.

### Finding S3-2 (M5): P3, guard_without_its_mirror
- **Verdict:** fixed.
- **claim:** B's copied days took `copyEvicted` from main's A instead of the chosen A.
- **New test:** "a copied B day evicts the hold the CHOSEN A evicted, not main's A".
  - In the lead world, R1 leaves ham refused by the clock alone, so a Biceps hold gives way.
  - Main evicts nothing.
  - B's copy must drop the same hold.
- **Mutant:** reddens 1 test.

### Finding S3-3 (M9): P3, guard_without_its_mirror
- **Verdict:** fixed.
- **claim:** a week-2 day with no budgeted row could take row 0 as its lead.
- **New test:** "a day with no budgeted row has no lead". Two holds; the result equals the switch-off run, and Side
  Hold gains.
- **Mutant:** reddens 1 test.

### Equivalent mutants
- **M14** (the A fallback to main): not reachable, because the capped world seats exactly main's rows. A comment at
  the branch now says so, and why the branch is kept. The gate pins A's worlds at lead / capped only.
- **M19** (`boundBy`, `>` vs `>=` on the clock): changes a diagnostic label at an exact boundary only.

### Sha check
Seat 3's restore check: all four files match the recorded sha256 values, and I re-checked them against `git show
HEAD:` before the fixes.

## The review commit

- **Product code:** `session_set_allocator.dart` only. It copies `leadSeats` for B's copied days, sorts them by day,
  updates the field doc, and adds the M14 comment. Plan output is unchanged: the goldens and the kill-switch golden
  were re-run.
- **Tests:**
  - `lead_first_allocator_behavioral_test.dart`: 37 tests, 2 new, and assertions added to 4.
  - `session_set_allocator_behavioral_test.dart`, `session_set_budget_consumers_test.dart`,
    `session_set_budget_wiring_test.dart` and `oi489_timed_hold_real_engine_test.dart`: the exact excuse maps.
  - `injury_recheck_v14_contract_test.dart`: the traced comment.
- **Docs:** the diagnose doc d4a7e2, the plan's line reference, and the OI-475 note.
- **Mutation of the review fixes:** 5 mutants (B1-B5), 5 red after one more fixture for the sort.

## Founder triage notes

The founder's standing directive is to carry the generator overhaul through its pipeline, so the verdict was set by
the author once every finding was closed. No finding reverses a recorded decision.

## Tuning entry
- **2026-11-13** - blast-radius platform - 14 findings (3 P2, 11 P3); 1 false_alarm (the trailer remark), 1
  orchestration-caused non-finding (the one-off red); tuning:
  - Never run the lens-6 mutation seat in parallel with seats that run tests on the same worktree. Its mutants leak
    into their compiles: seat 1 saw a red that was seat 3's mutant. Run it after the other seats, as §3 step 4 already
    says, or give it its own worktree copy.
  - In a world / fallback ladder, a fixture must assert which world was kept (`leadWorld`), not only the rows: three
    of the author's first-pass survivors were absorbed by the fallback.
  - Ask a seat to recompute every "the first such day" comment against the full measured set. Four comments in one
    diff named one day where 8 to 25 existed.
