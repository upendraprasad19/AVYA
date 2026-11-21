---
branch: coach-workout-parity-1c
scope: Coach workout parity 1c (Part 1c of docs/plans/coach-workout-parity-1c.md). Active Workout opens an exercise the AI coach already logged today as DONE with LOGGED IN CHAT. Re-opening adds sets, and only new sets are saved (appended to the coach's row). KEEP AS LOGGED undoes a re-open while nothing is checked. A sticky local coach_logged marker survives app appends, moves and key migration. The header and FINISH counts include the coach's sets, and three FINISH blocked lines are selected over the live exercise list. Part P ships first on exlog-type-filter-readers.
blast_radius: account
review_rounds: 6
ground_truth_verified: true
verdict: converged
mechanical_only: true
bpass: accepted
bpass_review: docs/reviews/coach-workout-parity-1c-bpass.md
---

# Plan-review record: coach workout parity 1c

Plan: `docs/plans/coach-workout-parity-1c.md`, Part 1c (rev 7). Every round used two context-blind Sonnet reviewers with an exhaustive read-only command list: seat A for ground truth, seat B for adversarial design and failure modes. Every round reviewed the revision that came out of the previous round's fixes.

Founder decisions (2026-11-10/11, binding):
- **Opening state:** a coach-logged exercise opens DONE with LOGGED IN CHAT.
- **Re-opening:** re-open adds sets and only new sets save. Any coach log counts as done.
- **All-logged day:** a coach-completed day keeps the zero-set FINISH block.
- **Copy:**
  - the undo button reads KEEP AS LOGGED;
  - the all-chat FINISH line: "Everything today is already logged in chat. Re-open an exercise to add sets, or cancel the workout.";
  - the mixed-day line: "No new sets logged this session (warm-ups don't count). Log one to complete, or cancel the workout."

## Round 1 (rev 1)
Both seats returned `needs-changes`.
- **P1s:** a mid-session sync (tick provider plus `initState` re-sync plus an "exempt" set) dropped entries and was not flag-gated. Swap and add wrote no entry. Re-open could not be undone. Typed-unsaved values were lost.
- **A-F2:** the FINISH PR scan never sees device rows. This became Part P.
- **Rev 2 direction:** snapshot the coach logs once at START.

## Round 2 (rev 2)
Both seats returned `needs-changes`, with no P1.
- A second START after an app append re-opened a coach exercise, allowing a double entry. Fix: the sticky `coach_logged` marker.
- The fully chat-logged FINISH dialog contradicted itself. The founder chose the all-chat line.
- Swap carried a reduced set count, and UNDO restored the wrong state. Fix: a mapped name opens DONE everywhere, and `plannedSets` comes only from the snapshot.

## Round 3 (rev 3)
Both seats returned `needs-changes`.
- Seeding re-opened rows from the coach's last set had no trigger in the card controllers. Per §4.12.1 the mechanism was removed, not patched.
- Fixes for the remaining findings:
  - an exercise introduced after START still allowed a double entry, so swap/add do a one-row read;
  - the marker was lost in the move-collision merge and in multi-member migrator groups, so both use OR semantics;
  - the FINISH-line predicate now looks at the live list.
- Part P was split into its own landing (`exlog-type-filter-readers`).

## Round 4 (rev 4)
Both seats returned `needs-changes`.
- **P1:** M34's lookup-order mutant was invisible.
- **P2s:**
  - unguarded shared snapshot reads, so an outer guard was added;
  - a mixed day with contradictory dialog lines (the founder chose the mixed-day line);
  - the meta text for timed and bodyweight cards;
  - the planned count for an introduced name.
- **Part P:** per-set maxima, and the badge stopped trusting `is_pr`.

## Round 5 (rev 5)
- **P1s:** one mutant per clause of the marker's compound OR, and per-method wrong-name fixtures.
- **Gate 19:** a pre-commit gate the plan did not know about. Fix: one `exlogRows` helper.
- **Coordinator decision:** the mixed-day line applies when any live slot has a chat entry.
- Part P was all MECHANICAL and converged.

## Round 6 (rev 6, Part 1c confirmation)
Both seats found no path to a double save, a lost set, or a dropped or leaked marker. Every Part 1c finding was MECHANICAL:
- a `_completing` fixture through `debugBeforeMarkGate`;
- explicit wrong-name fixtures;
- a shared `hasCheckedRow` helper for KEEP visibility and its guard;
- a direct marker assertion for M10c;
- distinct migrator mutants;
- `logSets`/`toggleSet` early returns.

Seat B's one design point (R6B-F2) was in Part P. The FINISH scan now skips session-date rows, so it shares one PR rule with the badge.

The round closes with `mechanical_only: true` (§4.12.6).

## B-pass
Accepted (2026-11-11): `docs/reviews/coach-workout-parity-1c-bpass.md`. Two context-blind Sonnet seats (S1 state and writers, S2 UI and test quality) ran on the staged diff after a green full suite (14,049 tests). There were 4 P2 findings and no P0 or P1. Each P2 is fixed with a mutation-proven test; one is a product fix in the card (the controllers rebuild when KEEP AS LOGGED returns an exercise to done). 10 coordinator mutants all went red.
