---
reviewed_at: 2026-11-15T10:20:00+05:30
staged_against: cf8c9ede52b323eb1ca6991b0f4ec65dc29ef136
branch: generator-step2d
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 3 P2 and 5 P3, all fixed in the review commit
---

# B-pass: generator-step2d (Unit 2D, a repeat phase at more minutes, OI-453)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head cf8c9ede, with CI green on that SHA
(PR #280: Analyze, Audit Gates, Build Check, Deno and the four unit-test shards). Two fresh Sonnet seats read the
three-dot diff `origin/main...cf8c9ede`. Neither ran anything, because a pre-push sweep was running in the same tree:
- **Seat A, the data path:** the read service, plan_generator (d50's scope), exercise_selector, models, the candidate
  and profile tests, and the registry.
- **Seat B, the allocation path:** session_set_allocator, periodization_engine, the behavioral test and the gate.

Both briefs quoted these recorded decisions:
- OI-453's hybrid design;
- d50 (one pass-through argument);
- d37 (no kill switch);
- d44 (a plain ledger for appended seats);
- d52 ("sets first" means the allocator's own targets);
- the rejected reschedule patch (round 2, B-1) and the rejected A-to-B seat copy (round 3, F2).

No finding re-opened one.

## Finding 1 - P2 - guard_without_its_mirror - an A-only day's candidates were screened against A only (seat A)
- **file:line:** lib/shared/repositories/plan_engine/exercise_selector.dart:503-512 (cf8c9ede)
- **claim:** On a day whose B list is its A list, the candidates serve both variants' weeks. They were screened against
  `pinnedLowerA` / `takenA` only.
  - The 5-day balanced build_muscle week mixes such days (Upper + Core) with B-list days (Legs).
  - So a same-movement partner of an earlier B-only candidate could sit in the same week 2 / 4.
  - Name collisions were caught later (the allocator's held set, `_dropHeldCandidates`). A partner of another
    candidate was not.
- **status:** fixed. `ExerciseSelector.sharedDayCandidatesFor` screens against both variants' pinned names and earlier
  candidates, and extends both taken sets. Tests:
  - the direct test `a day whose B is A screens against both variants`, which is red under M35, M36 and M37;
  - a real-library sweep over every 5-day balanced persona at 60 / 90 minutes, asserting no candidate repeats another
    in its variant's week. It is green with and without the fix: real data never hit the case, as the seat expected.

## Finding 2 - P2 - asserted_fixture_value - the week-2 reserve test had one day and equal A / B lists (seat B)
- **claim:** It could not see three faults:
  - a reserve taken from the wrong variant;
  - a reserve booked on the wrong day;
  - a gain on one day spending the weekly top an appended row needs on another.
- **status:** fixed. The new two-day test has different A and B pins and candidates per day, Chest rows walking the
  Chest week toward its top, and a custom filler of 0-10 sets on day 1's B list. That is 704 day comparisons.
  - M32 (variant flipped) and M33 (reserve booked on day 0) are red.
  - M33 first survived a version without the filler and was red once the filler made day 1's time tight.

## Finding 3 - P2 - asserted_fixture_value - the no-candidate test compared a run with itself (seat B)
- **status:** fixed. `SessionSetAllocator.allocateCoreForTest` exposes `_allocateCore`. The test now checks that
  `allocate` equals the core allocation over three fixtures, both 2A paths and both 6-day values:
  - no candidates;
  - two days at 45 minutes;
  - a candidate with no time left.
  It compares names, sets, both variants, the allowance stamp and `appendedA/B`.

## Finding 4 - P3 - asserted_fixture_value - a stale fixture comment (seat B)
- **status:** fixed. The comment said seven compounds; the fixture has three.

## Finding 5 - P3 - asserted_fixture_value - the gate priced rows by the plan row's first type (seat B)
- **claim:** The allocator prices a row by its library archetype. The gate's `_mainSeconds` passed no `rowsByName`.
- **status:** fixed. The gate passes the library rows by lowercase name.

## Finding 6 - P3 - guard_without_its_mirror - the 1e-6 margin had no mutant (seat B)
- **claim:** Costs carry the 1.20 time factor, so the margin is real. No test failed without it.
- **status:** fixed. Two tests search a timed custom filler's rest for a day whose leftover equals the seat's cost:
  - an exact 2-set seat is refused (M34 red);
  - an exact grow to 3 sets stops at 2 (M34b red).

## Finding 7 - P3 - writer_reader_drift - stale diagnose-doc line citations (seat A)
- **status:** fixed. Nine citations were re-derived after the review commit's own edits.

## Finding 8 - P3 - guard_without_its_mirror - the drift-gate allowance is name-global (seat A)
- **status:** fixed by documentation, as the seat offered. Every `_alwaysOk` entry is name-global. The comment now
  says so and names when the entry must go. Today `session_minutes` is a map key in lib/ only in the read service.

## Checked and clean (both seats)
- `minutesRose` is read from the OLD profile before generate() and the write. The resolution equals generateV4's.
- `last_phase_profile` has no sync, backup or restore path.
- plan_generator.dart changes in d50's three places only.
- Every `PopulatedDay(` site in lib/ was checked.
- Every registry `line_range` for a shifted file was checked. The review commit re-points `_isContraindicated`'s two
  ranges, which its own selector edit shifted by 24 lines.
- The reserve's soundness: fits are monotone, and the visit order of non-appended rows is unchanged.
- Weeks 1, 3 and 4.
- The 6-day alias and the `appendedB` edge cases.
- The gate's credit rule matches the allocator's.
- `plan_engine/**` is platform tier.

## Founder triage notes
Self-triaged under the standing directive ("Let's complete everything"). No finding needed a founder decision.

## Tuning entry

- **2026-11-15** - blast-radius platform - 8 findings (0 P0/P1, 3 P2, 5 P3); 0 false_alarm; tuning: two lessons.
  - A property sweep on the real library can be green with and without a fix when the data never reaches the case.
    Prove the guard on a pure seam with a crafted input, and keep the sweep only as reach.
  - A reserve or ledger test needs a fixture where the resource it books is the one that binds. M33 (a reserve
    booked on the wrong day) survived Chest rows walking the weekly top, which is not per-day. It went red only once
    a filler made one day's time tight.
