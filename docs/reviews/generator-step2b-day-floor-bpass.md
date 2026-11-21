---
reviewed_at: 2026-11-13T22:30:00+05:30
staged_against: d7013d297595507b8cdc7302b89f700dd4dbf4a7
branch: generator-step2b-day-floor
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 11
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 4 P2 and 6 P3 fixed in the review commit, 1 P3 equivalent with evidence
---

# B-pass: generator-step2b-day-floor (Unit 2B, the 3-exercise day floor, OI-452)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head d7013d29, with CI green on that SHA
(`land_pr.sh 263 --ci-only`, `result: ci-green`). Fresh Sonnet seats reviewed the three-dot diff `origin/main...HEAD`.

Each brief carried:
- the founder decisions d30-d33, the plan's rejected alternatives and its out-of-scope list, quoted;
- an exhaustive command list: read-only git, file reads, `dart analyze`, and the named `flutter test` files;
- a ban on `dart run scripts/*`, `scripts/*.sh`, network tools and every database statement.

The seats:
- Seat 1: the allocator logic and the kill switch. Lenses 1 and 3, lens 6 by reading, and plan conformance.
- Seat 2: tests, the shared oracle, the gate, the fixture and the docs. Lenses 8, 6, 7, and lens 1's inserted-lines
  check.
- Seat 3: mutation. Lens 6 by mutating three files under a backup / restore / sha256 protocol, on the post-fix tree,
  alone.

## Seat 1: allocator logic (0 P0-P2, 2 P3)

It found no logic defect. It answered each specific question with evidence:
- the stats always belong to the plan returned, across every world branch and the 6-day path;
- with the floor off, the code is byte-identical to origin/main in both 2A paths;
- no later pass grows a floored row or passes the floored lead + 1, except in 2A's main world (plan §7, already
  recorded);
- `firstLifts`, `leadSeats` and `belowFloor` read the floored state.

### Finding S1-1: P3, docs/naming (also seat 2, finding 2-2): fixed
Three places cited `test/plan_generator/day_floor_gate_test.dart`, a file the build had split into three: the SoT
registry reader, the nested `plan_engine/CLAUDE.md` and the OI-506 deletion list.
- Fix: the registry cites `test/helpers/day_floor_gate_lib.dart` (the three files); CLAUDE.md cites
  `day_floor_gate_*_test.dart`; OI-506 names the three files and the lib.
- The plan's §4 wording stays as history; §7 records the split.

### Finding S1-2: P3, guard_without_its_mirror (count target): fixed by comment and premise pin
`canFloor` does not exclude a target-removed slot. The seat showed this is unreachable: target removal needs
`rowsOf >= countMax >= 5`, and the floor acts only below 3 rows.
- Fix: the argument is written as a comment in `canFloor`.
- The behavioural test now pins the premise it rests on, every count max >= the floor's 3 (with seat 2's 2-1).

## Seat 2: tests, oracle, gate, docs (0 P0-P1, 2 P2, 4 P3)

It answered the specific questions:
- No re-recorded test lost an assertion; each keeps its original under `dayFloor: false`.
- The gate's floor-off digest does prove "floor off == main": an unread flag would floor the off world, and with 916
  thin day-weeks in the gate the digests would differ. `pinsDiffer` is the sound precondition for sharing the pins.

### Finding 2-1: P2, asserted_fixture_value: fixed
The count-target test asserted only `countMax(level) >= 5` and never called the allocator.
- Fix: rewritten as what it really is, a PREMISE pin. Every count max (`unknown` included) must be >= the floor's 3,
  the condition under which `canFloor` needs no target guard (S1-2).
- The test name and comment now say it is not a behaviour test.

### Finding 2-2: P2, stale citation: fixed (see S1-1)

### Finding 2-3: P3, the kill-switch `changed == 18`: fixed (comment)
`changed` compares two fixture values, so it guards the fixture's content (the sample holds days the floor changes),
not the live switch. The live check is `diffs`: an ignored switch in either 2A path turns the main-recorded floor-off
keys red. The comment now says so.

### Finding 2-4: P3, the oracle was coarser than the real excess: fixed (made exact)
- The week allowance was 2 per seat naming a group; the real excess can be 1.
- The time excuse was a seat's full seconds, not its overrun.
- Seats were matched by name, so a day listing one exercise twice would be over-excused.

Fix:
- `FloorSeat` gains `overBy` (each over-top group's exact excess, at most 2) and `overSeconds` (the part of the seat
  that did not fit the seconds left).
- The oracle sums those exactly and no longer matches by name; every caller was updated.
- New asserts: each seat in the five-day fixture adds `{Back: 2}` and 0 s; the clock fixture's `overSeconds` equals the
  day's overrun to 1e-6, not the seat's 336 s.
- Docs: registry, naming row, plan-engine-detail, diagnose F4.

### Finding 2-5: P3, weeks 1-4 asserted sets only: fixed
The week test now also asserts 3 rows a day in every week, so a later week dropping a floor seat reddens.

### Finding 2-6: P3, comment arithmetic: fixed
The session-cap test's comment now says why Row ends at 4: pass C grows the lead after the floor, Back 4 + 2 = 6 =
the cap.

## Seat 3: mutation

Seat 3 ran 32 new mutants on the post-fix working tree, across `day_floor_behavioral_test`,
`session_set_allocator_behavioral_test`, `exercise_count_band_behavioral_test`, `quads_credit_flag_consumers_test` and
`lead_first_allocator_behavioral_test`. Each mutant replaced exactly one occurrence, and the three files were restored
and sha256-checked after each one (all OK at the end; the coordinator re-checked against its own pre-dispatch sums).

- 26 were red:
  - the `overBy` cap dropped or set to 1;
  - `overBy` / `overSeconds` computed after `ledger.add`;
  - both `overSeconds` formula mutants;
  - the oracle dropping `overSeconds`;
  - rows read as budgeted-only;
  - `want` from `floorBase`;
  - `excessAfter` + 1;
  - three `floorPrefers` reversals or ties;
  - the label swap;
  - `reserveBlocked`;
  - the session cap `>=`;
  - four B-copy / stats-source mutants;
  - the per-variant flag in both paths;
  - the worlds chosen floor-on;
  - one floor round;
  - seats at 3 sets;
  - the 6-day re-run off.
- 6 were green. They are covered by the three findings below and one equivalent mutant.

### Finding 3-1: P2, guard_without_its_mirror (oracle per-group exactness): fixed
The oracle summing the first `overBy` value (m08) or a flat 2 per `overTop` group (m09) stayed green: every reader
fixture had one group at a full excess of 2.
- Fix: an oracle unit test over hand-built `AllocationStats`: one seat over by `{Chest: 1, Back: 2}`, two seats on
  one day with the same name, a second day, a day with none, and null stats. It asserts the per-group sums,
  `weekCeiling`, and the per-day `overSeconds`.
- m08 and m09 are now red, in that test alone.

### Finding 3-2: P2, guard_without_its_mirror (a group at or under its top): fixed
A group the seat takes exactly to its top (excess 0), or leaves under it, counting as over (m13 in the over count, m29
in `overTop` / `overBy`) or lowering the excess sum (m30) stayed green: the F2 fixtures had only over-top groups.
- Fix: two F2 fixtures in `day_floor_behavioral_test`:
  - X (Back + Biceps, Biceps landing exactly at 12) ties Y (Back) and is seated first, recording `{Back: 2}` only;
  - Y (Back) ties X (Back + Biceps, Biceps 10 under) and stays first.
- m13 and m29 are red in the first, m30 in the second.

### Finding 3-3: P3, the floor seat's `why` reset unpinned (m19): equivalent, no change
`why` is read only for slots that are not admitted: the label snapshot at `session_set_allocator.dart:792` and
`_label`'s removed branch at :1086. Nothing after the floor un-admits a slot: the only `removed = true` writes are at
:628 (the count target) and :688 (pass A), both before the floor at :794. A floor seat's `why` is therefore never read.
The reset mirrors pass A2's at :776.

### m06 (`overClock` `>` to `>=`): equivalent
It differs only when a seat's seconds equal the seconds left exactly. `overSeconds` is then 0 in both, and the oracle
reads only `overSeconds`.

## The review commit

The fixes for seats 1-3 land in one commit on top of d7013d29, which also carries this file, the plan-review record
(`bpass: accepted`) and the diagnose doc's B-pass section. After the fixes, the 14 test files that read the oracle or
pin the floor are green (206 passed, 1 opt-in report skip), including the three gate files and the kill-switch test.
`day_floor_behavioral_test` has 23 tests.

## Founder triage notes

Self-triaged under the standing directive (carry the unit through its pipeline). No P0 or P1. Every P2 and P3 is fixed in
the review commit or recorded with evidence above.

## Tuning entry

- **2026-11-13** - blast-radius platform - 11 findings (0 P0/P1, 4 P2, 7 P3); 0 false_alarm; tuning: a new oracle or
  test helper that is "exact" needs its own unit test over hand-built inputs with two groups at DIFFERENT excesses.
  Reader fixtures with one group at the full excess cannot tell an exact oracle from a per-seat flat one (m08 and m09
  survived every reader). For a "what counts as over" predicate, mutate `> 0` to `>= 0` and give it at-the-boundary
  and under-the-boundary fixtures.
