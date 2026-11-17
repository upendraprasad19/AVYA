---
reviewed_at: 2026-11-16T07:30:00+05:30
staged_against: 912aeacd2bd78503f9a9ca2ab81cec1b48b402e8
branch: generator-step3a
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 11
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 3 P2 and 8 P3; one P3 was a false alarm, the rest fixed in the B-pass commit
---

# B-pass: generator-step3a (Unit 3A, training follows the goal, OI-487 generator half)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head 912aeacd, with CI green on that SHA
(PR #286). Two fresh Sonnet seats read the three-dot diff `origin/main...912aeacd`:
- **Seat A, the data path, the docs and the fixture values:** read-only; recomputed the test literals by hand, checked
  every cited file:line and SoT range, scanned for secrets, swallowed function errors and unawaited sinks.
- **Seat B, the mechanisms:** ran the goal-reps, day-floor and swap-rest tests and mutated `periodization_engine.dart`
  and `session_set_allocator.dart` under a backup / sha256 protocol (restored, hashes equal).

Both briefs quoted the recorded decisions d3, d4, d58-d68, the stated equivalent mutants (BELOW2, TIE, MOST) and the
stated properties. No finding re-opened a decision.

## Finding 1 - P2 - guard_without_its_mirror - weeks 2-4 of the goal rep path had no semantic pin (seat B)
- **file:line:** lib/shared/repositories/plan_engine/periodization_engine.dart (the Cut / Maintain accessory clamp)
- **claim:** the e2e tests read week 1 only; a clamp applied in week 1 only (`weekIdx == 0 &&`) passed every fast test.
- **status:** accepted, fixed: "weeks 1-4 and the stash" (`goal_reps_behavioral_test.dart`): Cut press 8/8/6/6, raise
  14/14/12/11 and 10/10/10/10, Maintain press 10/10/8/8, the stash = week 3, every Cut / Maintain accessory in 10-15 in
  every week of phases 1-4. Red under the mutant (21 passed, 1 failed).

## Finding 2 - P2 - guard_without_its_mirror - the d65 trim's time credit was unpinned (seat B)
- **file:line:** lib/shared/repositories/plan_engine/session_set_allocator.dart (the trim's `ledger.add` seconds)
- **claim:** crediting 0 seconds for the cut set passed the day-floor file (LEDGER removed the whole call, so only the
  sets half was pinned).
- **status:** accepted, fixed: "the trim gives the cut set's seconds back to the day" (`day_floor_behavioral_test.dart`,
  24 minutes, 2C-b off): PullB fits the clock (overClock false); with 0 s credited it reads 114 s over. Red under the
  mutant (26 passed, 1 failed). A first draft at 20 minutes with 2C-b on failed the oracle: that run used the under-60
  allowance, which this file's oracle does not excuse; the fixture now turns 2C-b off.

## Finding 3 - P2 - writer_reader_drift - a bare SoT cite stale by three lines (seat A)
- **file:line:** docs/sot_registry.yaml (`periodization_engine.dart` writer `apply (stamps weekCharacter per week)`)
- **claim:** `line: 146` now points at `weekNumber:`; the cited `weekCharacter: _waveNames[weekIdx]` moved to 149 (the
  diff inserted three lines above it; the parity gate skips bare cites).
- **status:** accepted, fixed (149).

## Finding 4 - P3 - asserted_fixture_value - a no-range row escapes the table and the clamp, untested (seat B)
- **status:** accepted, fixed: test "a row with no rep range takes the legacy path for every goal" (10/10/8/8, stash 8,
  every goal); stated in the CLAUDE.md bullet and the diagnose's accepted consequences.

## Finding 5 - P3 - comments - the pre-3A lean described as universal; "read once" (seat B)
- **status:** accepted, fixed: `periodization_engine.dart` names the worlds the lean applies to; the `plan_generator.dart`
  comment (d61's line) says the Glutes credit reads the same switch through its default.

## Finding 6 - P3 - consequence - a floor-trimmed lead blocks pass C / D and week-2 gains on that day (seat B)
- **status:** accepted, documented (diagnose accepted consequences, the CLAUDE.md bullet); no stated property fails.

## Finding 7 - P3 - wording - "with the switch set every plan equals main" (seat B)
- **status:** no change needed: the plan, the contract and the SoT already say "over the 1,010 golden personas" / "where
  measured"; d65 is outside the switch and stated so.

## Finding 8 - P3 - docs - bug class 2.162 cited for "run the neighbouring gates" (seat A)
- **status:** false_alarm: 2.162's fix pattern ends with "Neighbouring gates ... must be run BEFORE the PR"; the cites
  now say "bug class 2.162's last point", as 2E's do.

## Finding 9 - P3 - closure ledger placeholder commit (seat A)
- **status:** accepted, fixed in the B-pass commit (`_commit` names the feat commit and the follow-ups).

## Finding 10 - P3 - the kill-switch fixture's label names main 708f9049 (seat A)
- **status:** accepted, fixed: the fixture's `_meta` and the test header add "equal on every key to main 2fe0ae52 (the
  merge base after 2E)", which seat A confirmed by diff; the header now cites OI-514.

## Finding 11 - P3 - a swap keeps the outgoing reps while its rest follows the incoming row (seat A)
- **status:** accepted, documented (diagnose accepted consequences; behaviour predates 3A).

## Founder triage notes

Self-triaged under the founder's standing directive ("complete everything"); no finding needed a founder decision.

## Tuning entry

- **2026-11-16** - blast-radius platform - 11 findings (0 P0/P1, 3 P2, 8 P3); 1 false_alarm; tuning: two lessons.
  - A wave of passes over a value (week 1 base, then weeks 2-4, then a clamp) needs a pin on every week the clamp can
    bind, not the week the table names; two review rounds and the gate all read week 1.
  - A ledger update has two halves (sets and seconds); a mutant that removes the whole call pins only the half some
    test reads. Mutate each argument on its own, and when the seconds are not observable, find the stat computed from
    them (here the floor seat's `overClock`) and sweep the session length for a value where the two worlds differ.
