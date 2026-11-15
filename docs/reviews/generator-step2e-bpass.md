---
reviewed_at: 2026-11-15T19:30:00+05:30
staged_against: 06bd06efa7973decef57c06cc630bba7470c4b8f
branch: generator-step2e
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, missing_input, asserted_fixture_value, guard_without_its_mirror, unawaited_no_error_sink]
findings_count: 8
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 3 P2 and 5 P3, all fixed in the B-pass commit
---

# B-pass: generator-step2e (Unit 2E, the arm swap under 60 minutes, OI-496)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head 06bd06ef, with CI green on that SHA
(PR #282). Two fresh Sonnet seats read the three-dot diff `origin/main...06bd06ef`:
- **Seat A, the data path, the docs and the fixture values:** read-only; recomputed the test literals and the gate's
  pinned counts by hand, checked every cited file:line.
- **Seat B, the allocator mechanism:** ran the arm-swap, allowance and weekly-minimum tests and the gate, and mutated
  `session_set_allocator.dart` under a backup / sha256 protocol (restored, sha 59162234... before and after).

Both briefs quoted the recorded decisions d51, d44, d45 / d49, d37, d38, d48 (with round 1's widening to the refused
2A opener), d53, the rejected `_dropSeat` patch, and the stated survivors. No finding re-opened one.

## Finding 1 - P2 - guard_without_its_mirror - the hold walk's evicted skip had no test (seat B)
- **file:line:** lib/shared/repositories/plan_engine/session_set_allocator.dart:1522 (06bd06ef)
- **claim:** Without `evicted.contains(ex)` a hold that pass A or R already evicted can be the victim: its seconds are
  credited back though never spent, and the arm row is seated with no row leaving. Every test stayed green with the
  skip removed.
- **status:** fixed. A probe sweep (84 cases, base against the mutant) found the shape: custom 6, both holds evicted,
  the curl refused; the mutant grows the day from 3 rows to 4. Pinned by "a hold that is already out of the day
  (evicted) is never a victim" (EVm red).

## Finding 2 - P3 - guard_without_its_mirror - the hold branch's keepsOpener had no test (seat B; KOh)
- **file:line:** session_set_allocator.dart:1526 (06bd06ef)
- **claim:** Replacing `keepsOpener(null) && armFits(...)` with `armFits(...)` left every test green (a stated
  survivor).
- **status:** fixed. Probe sweep (72 cases): fly the admitted lead, heavy the refused 2A opener, custom 6, hold0 1 set,
  hold1 8 sets, chin; the mutant swaps hold0 for a chin-up that would open the day. Pinned by "a hold victim is
  refused when the arm row would open the day" (KOh red). The diagnose doc no longer lists KOh as a survivor.

## Finding 3 - P2 - writer_reader_drift - the victim list in three docs missed round 2's exclusions (seat A)
- **file:line:** docs/sot_registry.yaml:11955; the diagnose doc's S2-S5 bullet; test/contracts/arm_swap_behavioral_test.dart:6;
  the plan's stated properties (line 128).
- **status:** fixed: each names the day-floor seat and the count-forced row; the registry also states the same
  allowance world.

## Finding 4 - P2 - writer_reader_drift - spentSeconds / resetSpentSeconds missing from the registry (seat A)
- **status:** fixed: named on the weekly_minimum `session_budget.dart` writer.

## Finding 5 - P3 - doc wording - "arm pair" defined per (variant, group) (seat A)
- **status:** fixed in naming_conventions.md: one arm group at 0 in exactly one variant (at most 2 per plan).

## Finding 6 - P3 - closure ledger placeholder commit (seat A)
- **status:** fixed: `_commit` names e39505a3 with the fix commits.

## Finding 7 - P3 - the merge-seam records (seat A)
- **status:** fixed: this file and docs/plan-reviews/generator-step2e.md land in the B-pass commit.

## Finding 8 - P3 - minimum-seat docs omit the swap's seat (seat A)
- **status:** fixed: the `AllocationStats.minimumSeats` field doc and the glossary row name it.

## Founder triage notes
Self-triaged under the standing directive ("let's complete everything"); every finding fixed, none false.

## Tuning entry

- **2026-11-15** - blast-radius platform - 8 findings (0 P0/P1, 3 P2, 5 P3); 0 false_alarm; tuning: one lesson.
  - A guard that is the mirror of a pinned guard (the hold branch of a two-branch walk) needs its own fixture; a
    probe sweep of base against the mutant, diffing outputs, finds the reaching shape in one run when hand-built
    fixtures keep missing it.
