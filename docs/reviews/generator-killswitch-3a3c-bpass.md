---
reviewed_at: 2026-11-17T14:44:00+05:30
staged_against: c413cd7806c315ca939017a9b23c80beb6ec93f4
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 fresh seats: A lib, B tests and fixtures, C docs and registries)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: accepted
verdict_note: all 10 findings accepted and fixed in the same batch (9 distinct, one reported by two seats); 0 false alarms; the reviewed head c413cd78 had CI green (4 shards).
---

# Code Review — generator-killswitch-3a3c (delete the 3A and 3C kill switches, OI-514 / OI-516)

Reviewed: `git diff origin/main...HEAD` at c413cd78 (3 ahead, 0 behind origin/main; CI green on that head via
`land_pr.sh 294 --ci-only`). Three context-blind Sonnet seats, read-only, each with an exhaustive command list and the
plan's decided items quoted (the 18 -> 28 re-pin, `CardioFinisher.debugReserve`, no finisher for Build, the
comment-only `plan_generator.dart` waiver). No seat mutated files: the author's 16 mutants (a)-(p), each red on named
tests, are recorded in plan §8; the seats judged pins by reading and arithmetic.

## What each seat checked and found clean

- **Seat A (lib/, lenses 1, 3, 6, 7):** no live reader or writer of `disable_goal_training` /
  `disable_cardio_finisher_shown` anywhere in lib, test, supabase, scripts or .claude; a stale stored key on a device is
  harmless (nothing reads it, no sync or restore allowlist names it). All three `weeklyBand` call sites, the one
  `GoalReps.base` caller, `restForGoal`, `quadPrimaryCreditsGlutes`, `CardioFinisher.plan` / `attach`,
  `shownFinisherMaps` and `FinisherShowContext` callers were followed to their call sites and are consistent; the old
  `_bands` and `_goalBands` hold the same keys and levels, so nothing falls through to `build_muscle` that did not before.
- **Seat B (test/, lenses 1, 6, 8):** `git diff c16ce1ea acc64f6a -- test/fixtures` shows only the two deleted
  fixtures (the two-tree oracle holds); the baseline JSON read back (1152 build, 2304 groups, `maxOver` 6,
  `identicalOff` 92); counts and digests equal plan §6; every `debugReserve = false` has a reset; the 8 crafted fixtures
  were re-derived by arithmetic and each has a discriminating twin (the rank-0 fixture is pinned by
  `leadWorld == 'lead'`, the rank-major vs day-major case differs by `[4,3]`/`[4]` against `[4,4]`/`[3]`).
- **Seat C (docs, lenses 1, 3):** the OI-514 / OI-516 entries moved verbatim and appended (closed_issues.md +22 / -0);
  the step-5 closure ledger counts equal its entries; blast radius `platform` is right for `plan_engine/**`; the
  `sot_registry.yaml` ranges for the touched files were checked against the code.

## Finding 1 — P2 — writer_reader_drift (seat B)
- **file:line:** `test/plan_generator/{lead_first,loaded_wins,balanced_week}_kill_switch_golden_test.dart` headers and
  test names.
- **claim:** they still said the fixture "is main 9fc3b043's / c6b1ee48's `generator_golden_hashes.json`" or "run r0's
  tree"; after c16ce1ea 480 of 1,010 keys (every lose_fat and general_fitness persona) differ from main's, and the
  fixtures' own `_meta` says 421cd2d2. The wording, not the pin, was wrong.
- **verification:** `python3 -I` read of each fixture's `_meta`; `git diff origin/main...HEAD` for the header lines.
- **status:** accepted, fixed (headers and test names now say the world recorded on 421cd2d2; no fixture or expectation changed).

## Finding 2 — P3 — writer_reader_drift (seat B)
- **file:line:** `test/helpers/day_floor_gate_lib.dart:17,20,103`, `test/helpers/day_floor_personas.dart:3`,
  `day_floor_kill_switch_test.dart:51`, the three `... OFF = main` test names in `day_floor_gate_{rep30,pairs_p1,pairs_p4}_test.dart`,
  and the `/* the finisher switch is set */` comments in `oi489_timed_hold_real_engine_test.dart:106` and
  `weekly_minimum_gate_test.dart:162`.
- **claim:** stale "main 8a2e1c5a" anchors and a switch that no longer exists.
- **verification:** `git grep -n -e 8a2e1c5a -e "OFF = main" -e "finisher switch is set" -- test/`
- **status:** accepted, fixed (comments and names only; no digest or tuple touched).

## Finding 3 — P3 — dead code (seat B)
- **file:line:** `lib/shared/repositories/plan_engine/cardio_finisher.dart` `roundRests` (`_buildFinisher`,
  `_hiitFinisher`, `_miniHiitFinisher`).
- **claim:** every caller passed `roundRests: true`; the `false` path (0 s round rest) had become unreachable once the
  `!enabled` branch was deleted.
- **verification:** `git grep -n roundRests -- lib test`
- **status:** accepted, fixed (parameter removed; `restSeconds` is 60 / 30; behaviour identical: the finisher and golden tests are green after the removal, and one mutant
  (the mini-HIIT `restSeconds: 30` -> `0`, confirmed applied with `grep -c`, restored by sha256) reddened 2 tests in
  `cardio_finisher_shown_pure_test` / `cardio_finisher_reservation_behavioral_test`).

## Finding 4 — P3 — writer_reader_drift (seat A, repeated by seat C)
- **file:line:** `lib/shared/repositories/plan_engine/finisher_show_context.dart:10` ("the profile or the switch");
  seat C added `session_budget.dart:331` ("an injury, the switch").
- **status:** accepted, fixed (both comments).

## Finding 5 — P3 — formatting (seat A)
- **file:line:** `plan_engine_flags.dart:65-66` two blank lines where the two getters were.
- **status:** accepted, fixed by hand (no `dart format`); the `docs/sot_registry.yaml` range for
  `isRestDayConsideringLogged` moved 515-520 -> 514-519 in the same commit and was re-opened by hand.

## Finding 6 — P3 — evidence no longer reproducible (seat C)
- **file:line:** `docs/audit/generator-step5.closure.yaml:17` (S5-ZERO-WEEKS): "the same audit with
  disable_cardio_finisher_shown set has 0 such cells".
- **status:** accepted, fixed (a dated `notes:` line: measured before the deletion; now reproduced with
  `CardioFinisher.debugReserve = false`).

## Finding 7 — P3 — stale metadata (seat C)
- **file:line:** `test/fixtures/generator_golden_hashes.json:3` `recorded_on` still reads "disable_cardio_finisher_shown
  default ON".
- **status:** accepted as documented, not edited: the file is byte-pinned by `generator_golden_test`, and a meta string
  edit would move a fixture the two-tree oracle promises is untouched. Plan §8 now names it and
  `goal_training_gate_baseline.json` (which names the keys on purpose) as the only two places the names remain outside
  retired-name docs.

## Finding 8 — P3 — plan record (seat C)
- **file:line:** plan §2.3 never said the founder granted the comment-only waiver; §8's "24 files of §3" could not be
  recomputed.
- **status:** accepted, fixed (§2.3: granted 2026-11-17, "1. Ok"; §8: 24 = the 23 `_test.dart` files commit 2 modifies
  plus the unchanged `generator_golden_test`, with the command that shows the 2 modified helpers and 5 deleted files).

## Finding 9 — P3 — wording (seat C)
- **file:line:** `docs/audit/closed_issues.md` OI-514 / OI-516 "Verified" lines read as prospective while the merge
  waits for the founder's remaining device checks.
- **status:** accepted as is: the same "closed by the carrying commit" convention is used by 59 other entries, and
  nothing merges before the founder reports those checks.

## Finding 10 — P3 — fixture meta (seat B, same file as Finding 7)
- Seat B reported the same stale `recorded_on` text and the baseline's `_meta` hit; folded into Finding 7.

## Founder triage notes
Triage by the author, 2026-11-17: 10 reported, 9 distinct, 0 false alarms. No finding changes a pin or a fixture.

## Tuning entry
- **2026-11-17** - blast-radius platform - 10 findings; 0 false_alarm; tuning: lens 6 gains a sub-check (a fixture whose
  outcome a fallback can reproduce needs a pin on which path ran; also a header that says "= main" goes stale the moment
  a fixture is re-recorded on another tree, so grep headers and test names for the old anchor after any re-record).
