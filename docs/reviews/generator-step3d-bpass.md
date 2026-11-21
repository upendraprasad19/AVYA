---
reviewed_at: 2026-11-16T23:45:00+05:30
staged_against: 543fa294558122791478f3afb9ccfb61d47f9d2f
branch: generator-step3d
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 5 P2 and 5 P3; 9 fixed in the B-pass commit, 1 (A-F4) no change with evidence plus its cloud half recorded on OI-174; none a false alarm
---

# B-pass: generator-step3d (Unit 3D-b, "Keep training Phase 1" is the Monday-aligned hold week, OI-175)

The self-initiated ≥account B-pass (§4.3), on the committed head 543fa294 with CI green on that SHA (PR #290). Two
fresh Sonnet seats read the three-dot diff `origin/main...543fa294`.
- **Seat A:** the write and read services and their contract tests. Only seat A ran tests or mutants: 9 mutants,
  with backups and sha256 restores.
- **Seat B:** the marker, both callers, the comment sweep and the records. Read-only.

The brief quoted the founder decisions (d57, d80) and the recorded choices: OI-125 out of scope, no memo (1.09 ms
measured), DEFECT-B not reachable pre-launch, the server half already merged as 3D-a. No finding re-opened a decision.
Every fix was mutated after it landed (10 mutants, all red, each file restored from a backup; diagnose `d3b7e5`,
B-pass section).

## Finding A-F2 - P2 - writer_reader_drift - a failed hold left stamped rows that raw readers count
- **file:line:** `lib/core/services/workout_schedule_write_service.dart` `_holdWeekLocked` (the row loop's failure exit)
- **claim:** a completed target row gains the three hold stamps before the loop finishes; a later failed row write
  returns `failed` with `plan_end` unmoved, so the row stays `is_hold: true` and `week: 4+n` but uncovered. The
  covered rule lives only in the hold family; `completedWeekNumbers` (`:1404`), `_withoutHoldRows`, `weekModeForRow`
  and `hold_week_labels.dart` `rowIsHold` read the raw stamp.
- **verification:** `git grep -n "is_hold" lib`; the sweep keeps completed rows past `plan_end`, and the orphan clean-up
  runs only on a later hold.
- **fix:** widened to the class: a copied planned row written before the failure is the same leak. `_rollBackHoldRows`
  restores every touched target, newest first: a prior row is rewritten through the same write path; a date with
  no prior row is deleted. The cloud half of that delete is the pre-existing OI-174 class (`_syncScheduledWorkouts`
  is upsert-only). It is recorded on OI-174 together with the new reader: 3D-a's server hold rule reads
  `week_number > 4` for the current IST week. Tests: the failed-write test now asserts the rollback, and a new case
  covers a completed and a planned target. Mutants MR1-MR3 are red.
- **status:** accepted

## Finding A-F1 - P2 - guard_without_its_mirror - the orphan gap's lower bound had no test
- **file:line:** `workout_schedule_write_service.dart` `_clearOrphanHoldRows` (`!day.isAfter(afterDay)`)
- **claim:** including the `plan_end` day in the gap deletes H(n-1)'s Sunday (a rest row) when H(n) is written; the
  mutant left 22/22 green.
- **fix:** the H1 -> H2 -> H3 test asserts H1's and H2's Sundays survive and `holdWeeks()` is [1, 2, 3]. MR4 red.
- **status:** accepted

## Finding A-F3 - P3 - writer_reader_drift (inserted lines) - stale SoT line ranges
- **file:line:** `docs/sot_registry.yaml`, the seam entry `1007-1032`, plus six read-service ranges whose bodies
  outran them.
- **fix:** every range citing the touched files was recomputed from its anchor with a brace-matcher: the seam is now
  1264-1288; `currentPhaseCompletionRate`, `currentWeekColumnProjection`, `pastPhaseBlocks`, `_scheduleRowsBefore`,
  `pastPhaseBlocksForDisplay`, `nextPhaseStartDate` and the class were recomputed. The write service (+42 lines)
  moved to 36-548 and `holdWeek` to 211-508 (three entries); `keepTrainingPhase1` is 29-77.
- **status:** accepted

## Finding A-F4 - P3 - writer_reader_drift - an un-stamped completed orphan keeps `week: 4+n`; raw deletes stay local
- **claim 1:** no change. Orphan-gap rows are dated before this week's Monday, so neither today's card nor the
  server's current-IST-week rule ever sees them, and every other `week` reader returns null above 4.
- **claim 2:** a local `box.delete` never reaches the cloud. This is the pre-existing OI-174 class; it is recorded
  there with the new server reader.
- **status:** accepted (no code change; OI-174 bullet)

## Finding B-F1 - P2 - guard_without_its_mirror - five caller arms had no test
- **file:line:** `test/features/train/hold_week_callers_test.dart` against `keep_training_phase1_action.dart` and
  `plan_expired_card.dart`
- **fix:** six new tests:
  - graduation: alreadyHolding (snackbar and `/train`, no second hold), noPlan, a write that throws, and inFlight;
  - the card: failed and inFlight.

  Mutants MC1, MC2, MC4, MC5 and MC6 are red.
- **status:** accepted

## Finding B-F2 - P2 - writer_reader_drift (records) - OI-60 still OPEN for a deleted flag
- **fix:** OI-60 archived append-only to `closed_issues.md` (+87 / -0 lines), its Closed line citing the deploys.
  A sweep beyond the finding fixed two more:
  - OI-188 defect 1 ("LIVE: `holdWeeksEnabled` defaults false") is marked fixed;
  - OI-95's flag mention is marked deleted.
- **status:** accepted

## Finding B-F3 - P3 - docs - OI-166's line asserted both "OI-175 closed" and "stays open until OI-175 lands"
- **fix:** the tail now says the marker fixed the highlight; OPEN for OI-190 only.
- **status:** accepted

## Finding B-F4 - P3 - asserted_fixture_value - "no `==` override on purpose" was not load-bearing
- **fix:** the comment in `train_provider.dart` and in the marker test reworded (a tap on the default week changes
  `picked`, so a value `==` would notify too).
- **status:** accepted

## Finding B-F5 - P3 - test passes for the wrong reason - the selected-week invalidation was unobservable
- **fix:** the graduation written test picks W2 before the tap and asserts the pick is cleared (week 4, picked
  false). MC3 red.
- **status:** accepted

## Finding B-F6 - P3 - lint - two `use_build_context_synchronously` infos
- **fix:** explicit `if (!context.mounted) return;` in both arms (analyze clean).
- **status:** accepted

## Founder triage notes
Self-triaged under the standing directive ("Let's complete everything"). Seat A's M1/M2 survivors (the double-tap
comparison) are equivalent: a covered hold's last date is a Sunday, never the Monday.

## Tuning entry

- **2026-11-16** - blast-radius platform - 10 findings (0 P0/P1, 5 P2, 5 P3); 0 false_alarm; tuning: two lessons.
  - A design that relies on "uncovered rows are invisible" is only as good as its LEAST careful reader. Seat A found
    four raw readers of the stamp that skip the covered rule. When a write can stop half-way, ask for every reader of
    the stamped field (`git grep` the key), not only the family the author changed; prefer putting the rows back
    over hoping every reader filters.
  - Split seats by write-permission, not only by area: one seat that runs tests and mutants, the other read-only.
    Two flutter runs in one tree collide, and the read-only seat found the records gap (OI-60) that a code-focused
    seat skips.
