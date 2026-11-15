---
reviewed_at: 2026-11-15T09:30:00+05:30
staged_against: 1553cd3b9d438ebade2b3c709ea5e4409bf0b680
branch: generator-step2c-b
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
verdict_note: self-triaged under the standing directive; 1 P1, 4 P2, 4 P3; 8 fixed in the review commit, 1 kept as a recorded decision (chip wording at 60 / 90, with the reason)
---

# B-pass: generator-step2c-b (Unit 2C-b, the weekly minimum and the under-60 allowance)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head 1553cd3b, which was CI-green
(`land_pr.sh 279 --ci-only`, `result: ci-green`). That head already carried CI round 1's fixes: the row guard, the
2B gate harness and `walkedTargets` (diagnose e9b3d7, "CI round 1"). Two fresh Sonnet seats reviewed the three-dot
diff `origin/main...HEAD`. Each brief had the preamble, quoted the recorded decisions (d35, d38, d42, d44, d45, d47,
d48, d49, d37) and the plan's rejected alternatives, and gave an exhaustive command list:
- **Seat 1, the engine:** `session_set_allocator`, `session_budget`, `models` and `periodization_engine`. Lenses 1, 3,
  6 and 7. It could mutate the three engine files under a backup / restore / sha256 protocol and run one scratch test.
  It restored and sha-checked every file, and deleted its scratch test.
- **Seat 2, the tests, the oracle and the documents:** lenses 1 (the inserted-lines sub-check), 6 and 8. Read only;
  it ran no tests.

## Finding 1 — P1 — guard_without_its_mirror (seat 1)
- **file:line:** lib/shared/repositories/plan_engine/session_set_allocator.dart, the walk's `if (at >= base) moved[bd]++;`
- **claim:**
  - One slot can be the cheapest for two target groups. The first group moves it; the second finds it at the
    segment's start and counts it again.
  - The next target then lands one place too late, behind a non-target row, so the count refuses it and a d38 focus
    group stays at 0.
  - Repro: one day on the 6-day path, 60 minutes, beginner, focus {Biceps, Shoulders, Triceps}. Before:
    [bench 3, cu0 2, cu1 2, fly 3, dual 5]. After: [bench 5, cu0 2, cu1 2, dual 5, tri 5].
- **verification:** `test/contracts/weekly_minimum_behavioral_test.dart` "the walk: two targets on one slot". It is
  red with the old line (mutant M33) and green with the fix.
- **suggested-fix:** `if (at >= base + moved[bd]) moved[bd]++;`
- **status:** accepted, fixed.
  - The 2,304-plan grid is byte-identical with the fix: the 30 / 45 gate ON digest 7420fa32 is unchanged, the 60 / 90
    hash is ab71bd63 again, golden and all 12 day-floor blocks are green.
  - The defect needs one library row crediting two target groups on a count-bound day, and the no-injury grid holds
    none.

## Finding 2 — P2 — asserted_fixture_value (seat 2)
- **file:line:** docs/diagnoses/2026-11-14-generator-weekly-minimum-e9b3d7.md, the Mutations table, column S
- **claim:** S's earlier rows were measured before the sweep digest existed (M01 and M08 green against a digest that
  must move).
- **status:** accepted, fixed. All 33 mutants were re-measured against W and S on the review tree, and the table was
  rewritten from that run. Column G is kept from the 3e6bcc77 run, because the fixes moved no grid plan.

## Finding 3 — P2 — guard_without_its_mirror (seat 2)
- **file:line:** test/helpers/day_floor_gate_lib.dart, the 2C-b swap excuse
- **claim:** a swap excused the dropped rows without checking that their groups stay trained, so a real loss could
  pass as a swap.
- **status:** accepted, fixed. A swap now also needs:
  - one new row per dropped row;
  - every group of a dropped row still trained that week (a budgeted ON row or a kept hold), else `lost`.

  The swap counts are unchanged: pairs_p1 10 / 6, pairs_p4 4 / 6.
  - Protect-first plus the protective fallback removed together leave pairs_p1 bodyweight unchanged. The injured blocks
    never put a target on a protected group's only row, so the check is a backstop there.
  - Inverting the check reddens the block, which shows it runs and reads real groups.

## Finding 4 — P2 — asserted_fixture_value (seat 2)
- **file:line:** docs/naming_conventions.md "weekly minimum"; docs/audit/open_issues.md, the OI-475 note
- **claim:** "every group a plan trains gets at least 2 sets" overclaims, since 71 zero-week pairs remain.
- **status:** accepted, fixed. Both now say it is a target, not a guarantee, and give the measured 134 -> 71.

## Finding 5 — P2 — missing_input (seat 1)
- **file:line:** docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md §2 S4
- **claim:** the plan still said the allowance is 300 s; it was built at 285 s (d47).
- **status:** accepted, fixed. §2 S4 now says 285 s as built (d47) and keeps v1-v4's 300 s as history.

## Finding 6 — P3 — guard_without_its_mirror (seat 1)
- **file:line:** test/plan_generator/plan_audit/plan_audit_lib.dart (over-time bound); edit_profile_screen.dart:1169 (chip)
- **claim:** the +6 audit bound applied at 60 and 90 too, where no allowance exists. The chip reads "About" at all four
  lengths.
- **status:** bound accepted and fixed: `minutes < 60 ? 6 : 5`, with both sides pinned in `plan_audit_lib_test`. The
  2,304-plan audit re-run is unchanged at 965 / 1,339 / 0, and no 60 / 90 plan gains an over_time flag. The chip
  wording is KEPT (`false_alarm` for the chip half). The count floor's forcing could already run a 60 / 90-minute day
  up to 5 minutes over before 2C-b, so "Up to" was never true at any length. "About" fits all four options. The
  wording was the parent plan's round-2 A-6 change.

## Finding 7 — P3 — stale record (seat 2)
- **file:line:** docs/audit/generator-step2c-b.closure.yaml
- **claim:** every `commit:` read "uncommitted at authoring", and C2CB-2 said "rows <= R".
- **status:** accepted, fixed. The anchors now point at 3e6bcc77 and 1553cd3b (the review fixes have their own
  entries), and C2CB-2 says rows = R.

## Finding 8 — P3 — weak tests (seat 2)
- **file:line:** test/contracts/session_allowance_behavioral_test.dart; test/plan_generator/session_set_budget_gate_test.dart
- **claim:**
  - (a) "adds sets" passed with `>=`.
  - (b) the readers test's name implied it proves the reader follows the stamp.
  - (c) a dead `fewerRows` counter.
  - (d) the budget gate stacked the forcing excuse on the allowance.
- **status:** accepted, fixed.
  - (a) Now `greaterThan`. Mutant M01 now reddens this test itself.
  - (b) The test name points at the gate and M05.
  - (c) The counter is removed.
  - (d) A stamped plan's `forcedPart` is 0 (never stacked, d42 / d47). The gate is green.

## Finding 9 — P3 — number nits (seat 2)
- **claim:**
  - 860 vs 861 short day-weeks;
  - "30 mutants" (the table holds more);
  - the day-floor comments dated 2026-11-15 while the commits are dated 2026-11-14.
- **status:**
  - 861 fixed (467 + 394) in the diagnose doc and plan-engine-detail.md.
  - The mutant count is restated from the re-measured table.
  - The dates are a `false_alarm`: the repo dates in IST and the comments were written after midnight IST; git
    shows UTC.

## Checked and clean (both seats, condensed)
- **The allowance stamp:** it reaches `_weekTwoGains` on every path. `VolumeTitration` never takes the allowance.
- **Copied days:** they inherit `minimumSeats` and `walkedTargets`.
- **The switch:** OFF equals R; every `balancedWeek` read site is listed.
- **Boundaries:** 59 / 60, 44 / 45 and 5- / 6-day are consistent, and the constants 285 / 300 / 45 / 60 / 4 / 2 agree
  in code.
- **SoT line ranges:** every `edit_profile_screen.dart` range still covers its method after the main sync.
- **Gate and audit arithmetic:**
  - 1,152 = 4 × 4 × 3 × 4 × 2 × 3;
  - verdict sums 965 / 886;
  - zero-week sums 71 / 132 (+2 at 60 / 90 = 134);
  - 102 - 23 = 79.
- Both seats confirmed the six surviving mutants (M10, M11, M12, M15, M16, M17) as stated. Seat 1 scanned 300
  crafted days without reaching M11 or M12.

## Founder triage notes
Self-triaged under the standing directive (generator steps: commit, push, PR and merge once reviews and CI pass).

## Tuning entry

- **2026-11-15** - blast-radius platform - 9 findings (1 P1, 4 P2, 4 P3); 2 false_alarm in part (the dates; the chip half
  of finding 6); tuning: a walk / reorder that moves shared slots needs a "one slot, two targets" fixture. Seat 1 found
  the P1 only by building a slot that credits two target groups, which none of 30 mutants or the grid exercised. Add
  "two targets on one slot" to lens 6's mirror list for any reorder pass. Seat 2's "the S column predates the digest"
  is the second instance of a mutation table measured before its strongest test existed: re-measure the table after
  every test added to it.
