---
reviewed_at: 2026-11-26T22:30:00+05:30
staged_against: 666760a004a48716242c1a8505e4fe5f9316912c
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 14
verdict: accepted
verdict_note: every finding fixed in 63ffa5fb and the follow-on commit, or closed as an equivalent mutant with the reason below
---

# Code Review (B-pass) — OI-348 Landing 3d (missed-day rescue)

PR https://github.com/upendraprasad19/AVYA/pull/361. Two context-blind Sonnet seats on commit 666760a0. Seat A
ran the read-only lenses 1-8. Seat B ran the mutation lens in a scratch detached worktree: 54 mutants, 41 killed,
13 survived, no compile errors, every file restored by copy with its sha256 checked.

## Seat A

### Finding A1 — P1 — writer_reader_drift
- **file:line:** lib/core/services/streak_progress_service.dart (settleRescueRefunds, the `is_swapped` test)
- **claim:** `DaySwapRules.landed` writes `is_swapped` only when content lands away from its origin. Take a PRO user who swapped Wed (rest) with Fri (workout) on Tue, missed Wed, and spent a freeze on it. Rescuing Wed into Fri sends both contents home, so both rows lose the markers. The refund then never comes, and the rollover heal never pays it either.
- **verification:** `grep -n "origin != toDate" lib/core/services/day_swap/day_swap_rules.dart`
- **disposition:** the `is_swapped` test is dropped. Plan-review round 3 (R3-2) had added it against hold and copy-week copies, and that decision was wrong. Both copy paths shift whole weeks (k != 0) and never re-date `rescued_into`, so the same-week test already refuses every copy. T7i covers the real path; T7h covers the copy.
- **status:** accepted (63ffa5fb)

### Finding A2 — P2 — missing_input
- **file:line:** lib/core/services/swap_service.dart `_lockFor`
- **claim:** a day before the user's anchor (onboarding or first log) was offered as "missed". The streak and adherence walks stop at that anchor.
- **disposition:** a day before `WorkoutRepository.earliestUserAnchorKey()` stays `past` (T1c, including the onboarding day itself).
- **status:** accepted (63ffa5fb)

### Finding A3 — P2 — writer_reader_drift (SoT line ranges)
- **claim:** registry cites in the diffed files had not been shifted.
- **disposition:** I mapped every structured cite of every diffed file through the `git diff -U0` hunks: 19 shifted, plus 3 entries this branch had written against the pre-fold code. A first pass also shifted whole-file `1-9999` sentinels and one `supabase/` cite. The parity gate caught that; I redid the pass keyed by registry line position. Parity is green.
- **status:** accepted (63ffa5fb)

### Finding A4 — P3 — guard_without_its_mirror (kill switch claim)
- **claim:** the flag comment said that with the switch set everything is "exactly what it was". The locked-source picker line and the freeze-chip refresh are not behind it.
- **disposition:** both are fixes of their own and are deliberately not switched. The comment now says so.
- **status:** accepted (63ffa5fb)

### Finding A5 — P3 — picker label
- **claim:** with a missed source, a future target showed a `PAST` chip.
- **disposition:** when the refusal is about the source, the chip reads `TODAY ONLY` (widget test).
- **status:** accepted (63ffa5fb)

### Finding A6a — P3 — capped refund lost
- **claim:** a capped settle still wrote the marker, so the refund was gone for good. A PRO user read as free at rollover would hit this.
- **disposition:** a marker is written only for the dates actually paid, so a date held back stays owed (T7e2, T7e3, T7e4).
- **status:** accepted (63ffa5fb)

### Finding A6b — P3 — Sunday-midnight settle
- **claim:** a settle that runs after midnight Sunday no longer sees last week's date.
- **disposition:** Monday's weekly refill restores the stock anyway, so nothing is lost that the refill does not give back.
- **status:** false_alarm

### Finding A7 — P3 — SoT manifest
- **disposition:** added the `syncFreezes` / conflict-retry / restore merge readers in `sync_restore_completeness.dart` and the `commitConsume` write-back.
- **status:** accepted (63ffa5fb)

## Seat B (mutation lens)

### Finding B1 — P2 — the drag target rule has no test (M03 argument order, M31 kill switch)
- **disposition:** extracted to the pure `DaySwapDragWrapper.dropTargetValid`, which the widget calls. New test M03/M31 covers both directions, the kill switch and `movable`.
- **status:** accepted

### Finding B2 — P2 — kill switch in the settle (M30); rollover wiring (M39)
- **disposition:** a settle test on a rescued row with the switch set, plus its mirror. A `runRolloverNow` behavioural test in `day_rollover_provider_invalidation_behavioral_test.dart` checks that the marker appears.
- **status:** accepted

### Finding B3 — P2 — never lowering an above-cap count (M14)
- **disposition:** test added. Since the A6a fold, M14 is equivalent: `given <= 0` returns before any write.
- **status:** accepted

### Finding B4 — P2 — `_weekHostsRescue` same-week test (M42)
- **disposition:** equivalent. `weekStates` reads today's row from that week's own map, which is null outside it, and an engine pair is same-week (`pairRefusal`) and refused by `pairLock` when both dates are past. The behaviour is pinned anyway.
- **status:** false_alarm

### Finding B5 — P2 — host requires `status rest` (M44)
- **disposition:** test with today = `type rest, status planned`.
- **status:** accepted

### Finding B6 — P2 — Monday bound (M07)
- **disposition:** test for a freeze spent on Monday and then rescued.
- **status:** accepted

### Finding B7 — P3 — `type rest` (M11), notice decrement (M46), same-week `into` (M13)
- **disposition:** one test each. After A1, `type rest` is the only shape test left, so it is no longer defence in depth.
- **status:** accepted

Equivalent mutants kept as such:
- M08 / M09: the engine always writes `rescued_into = today`, which is after D in the same week.
- M47: differs only when the count is stored as 0 alongside a true flag.

The suggestion to re-run the old engine suite with the switch set was not taken. Seat A confirmed the OFF engine path is the old loop verbatim, and M28/M30/M31/M32 now pin each switch site.

Re-run after the folds: M03, M31, M30, M07, M11, M13, M46, M44 and M39 are all red; M14 and M42 are green, both equivalent (reasons above).

## Founder triage notes
Self-triaged under the standing review-CI permission. Every finding is fixed or closed with a reason. No founder decision was reopened.

## Tuning entry
- **2026-11-26** - blast-radius platform - 14 findings; 2 false_alarm; tuning: a plan-review fold can be wrong. Seat A's P1 reversed a round-3 requirement (`is_swapped`), so when a reviewer says a fix "also requires X", the B-pass brief should ask which REAL path produces each row shape the guard rejects. Also: map SoT cites by registry line position, never by (file, text), because duplicate cite texts and the `1-9999` sentinels get rewritten.
