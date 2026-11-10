---
reviewed_at: 2026-11-10T20:24:45+05:30
staged_against: coach-workout-parity ea37ed59..ca96e754 (1a f3928922 + 1b ca96e754), rebased on origin/main ea37ed59
blast_radius: account
reviewer: three fresh context-blind Sonnet seats (adversarial B-pass; seat A the 1b rule and its four doors, seat B the 1a bookkeeping step, seat C Train UI + tests + documents against code)
lens_set: [guard_without_its_mirror, writer_reader_drift, unawaited_no_error_sink, function_exception_swallow, asserted_fixture_value, missing_input, secrets_in_tree, blast_radius_mismatch]
findings_count: 17
verdict: accepted
verdict_note: no P0; one P1 and every P2/P3 fixed in this batch except two reasoned no-change items (seat B F3, F4); fixes mutation-proven (docs/diagnoses/2026-11-10-coach-card-marks-uncountable-days-24e630.md, "B-pass mutations")
---

# Code Review (B-pass) — coach workout parity 1a + 1b (`coach-workout-parity`)

Three fresh, context-blind Sonnet seats reviewed `git diff ea37ed59..ca96e754` read-only. Their command lists were
exhaustive: read-only git, file reads, `dart analyze` on a changed file, `flutter test` on named files, and
`python3 -I` for counting. They had no `dart run scripts/*`, no `scripts/*.sh`, no network and no database statement.
Each brief carried the founder decisions so that intended behaviour was not reported. None carried the author's
conclusions.
- Seat C ran its five test files: 127 pass.
- Seats A and B read the code only.
- Every claim below was re-checked by the author against the code before triage. Three of seat C's line claims in
  F4 were themselves wrong (`checkAll` 93, `profile_provider` 313 and the preview sheet's 30 are correct).

**Verdict: accepted.** No P0. One P1 (seat B F1), fixed. Every P2 and P3 is fixed, except two items that stay as
they are, each with its reason below. The fixes are covered by 12 mutants: 11 reddened a named test, and 1 is
equivalent (reason recorded). The table is in the 24e630 diagnose doc.

## Seat B — slice 1a bookkeeping

### Finding B1 — P1 — guard_without_its_mirror / refactor-onto-shared-helper
- **file:line:** lib/features/train/services/workout_completion_bookkeeping.dart (step 1b, the restore gate)
- **claim:** The restore-settled gate returned straight after the count. So an Active Workout finish before the
  restore settled skipped `last_workout_date`, badges and the rank check. The old `_persistCompletion` ran all three
  unconditionally; only its reckon was gated.
- **verification:** `git show ea37ed59:lib/features/train/providers/train_provider.dart | sed -n 2255,2370p`
- **status:** accepted, fixed. Only the streak steps (reckon, weekly, streak row) wait for the restore.
  `last_workout_date` (later-wins), badges and rank (unlock or promote only) now run. Test: "restore NOT settled …";
  mutant M01.

### Finding B2 — P2 — guard_without_its_mirror (owner)
- **claim:** There was no owner re-check after the count's await or after step 4's await. A switch there would write
  the old account's streak row, badges and rank into the new account.
- **status:** accepted, fixed. `_ownerChanged` now runs after the prompt resolve, after the count and after the
  progress write. Tests: "the owner changes mid-step" (3 cases); mutants M03, M04. M02 is equivalent (see the
  diagnose doc).

### Finding B3 — P2 — guard_without_its_mirror (restore in flight)
- **claim:** Before the restore lands, a day completed on another device can look new locally, and +1 there is
  permanent.
- **status:** no change, reasoned.
  - The suggested fix was to defer the +1 while the restore is unsettled. That under-counts permanently in the
    failed-restore case. Local progress carries the cloud count N while local `wlog_` rows are partial, so
    `max(N, days)` never adds today. The next completion after the settle adds only its own day.
  - The over-count needs the same day completed on two devices inside one restore window, with progress restored
    before that day's schedule row. The old code had the same +1.
  - The seat agreed it is "not worse than before".

### Finding B4 — P3 — writer_reader_drift (untyped `wlog_`)
- **claim:** A pre-backfill `wlog_` row with no `type` makes `newlyCompleted` false, while
  `completedWorkoutDayCount` ignores the row, so the day is under-counted.
- **status:** no change, reasoned.
  - An untyped `wlog_` row was written by an old door that already counted that day with an unconditional +1.
  - Treating the row as not counted would double a day permanently.
  - The current choice can only under-count, which is the recoverable direction (the heal).
  - `wlog_type_backfill_migrator` tags such rows.

## Seat A — slice 1b rule and doors

### Finding A1 — P2 — function_exception_swallow
- **claim:** The backstop resolved `completion_prompt_<date>` even when `markCompleted` failed. The tile was the
  user's way to finish the day.
- **status:** accepted, fixed. The resolve moved into `afterCompletion` step 0b, which runs only after a successful
  mark. Test: "the backstop: a FAILED mark leaves the day's tile open"; mutant M06.

### Finding A2 — P2 — function_exception_swallow
- **claim:** A throw between the decision and the last write escaped `submitWorkoutDraft`, leaving the card with no
  saved state.
- **status:** accepted, fixed. The block has its own try/catch: `markFailed`, or `completed` when the day was
  already marked. Test: "the chat card: a throw after the mark …"; mutant M08.

### Finding A3 — P2 — guard_without_its_mirror (owner before the post-mark resolve)
- **status:** accepted, fixed by the same move. Step 0b runs after the step's owner guard and is followed by another
  re-check. Test: "the owner changed: the prompt is not resolved".

### Finding A4 — P3 — writer_reader_drift (stale tile after another door completes)
- **status:** accepted, fixed. Step 0b resolves the prompt for every door, Active Workout included. Test: "step 0b:
  the day's prompt is resolved for every door"; mutant M05.

### Finding A5 — P3 — race (0 s mark wipes a stored duration)
- **status:** accepted, fixed. `markCompleted` keeps a stored positive duration when a 0 s mark follows; a real
  duration still replaces it (the update contract). Test: "markCompleted: a 0 s mark …"; mutant M09.

### Finding A6 — P3 — guard_without_its_mirror (raw payload date)
- **status:** accepted, fixed. The backstop uses `istDateStr(date)` and logs `derived_completion_date_normalised` on
  a mismatch. Test: "the backstop: a payload date that is not plain yyyy-MM-dd …"; mutant M07. The first version of
  this test was vacuous on 2026-11-10; that is recorded in the diagnose doc.

## Seat C — Train UI, tests, documents

### Finding C1 — P2 — guard_without_its_mirror (disposed mid-tap)
- **status:** accepted, fixed. The container is captured before the await, and the invalidation no longer waits for
  `mounted`. Test: "the row collapses mid-tap …"; mutant M10.

### Finding C2 — P2 — blast_radius_mismatch
- **status:** accepted, fixed. `coach_day_completion.dart` and `workout_completion_bookkeeping.dart` are pinned at
  `account` in `docs/blast_radius.yaml`. Checked with `blast_radius_from_diff.dart`: both account, `week_rows.dart`
  still feature.

### Finding C3 — P2 — writer_reader_drift (registry ranges)
- **status:** accepted, fixed.
  - `markCompleted` 581-707.
  - `send` 784-1070 in both entries, with the chat call sites now `:896` and `:976`.
  - Every range into the files this fix round changed was remapped through the diff hunks by script (net +9 in
    `workout_write_service.dart`), with two anchors spot-checked. The parity gate passes.

### Finding C4 — P3 — doc line cites
- **status:** accepted, fixed where the claim held: `afterCompletion` 104, `newlyCompleted` 621, the card's decision
  460, `_buildCompactRow` 125, `_buildPlannedExpansion` 6. Three of the seat's claims were wrong and stay as they
  were: `checkAll` 93, `profile_provider` 313, the preview sheet's 30.

### Finding C5 — P3 — missing_input (gate vs row source)
- **status:** accepted, fixed for the action. LOGGED SO FAR and COMPLETE WORKOUT show only when the rendered rows list
  is non-empty. Test: "a log KEY for today whose row is stamped another day …"; mutant M12.
- The week row's IN PROGRESS chip still reads the key scan. A key under that date does exist, and the chip takes no
  action.

### Finding C6 — P3 — test gap (`_busy`)
- **status:** accepted, fixed. Test: "a double tap runs the completion once" (one bookkeeping run and no queued second
  snackbar); mutant M11.

### Finding C7 — P3 — Gate 19 baseline growth
- **status:** accepted, documented. The eight lines are heuristic false positives: the file first named `'wlog_'` in
  1a, and the fields are `exlog_` reads. The explanation is in `docs/diagnoses/2026-11-10-coach-completion-skips-bookkeeping-0ebfcb.md`.

## Founder triage notes
Self-triaged per §4.3; the verdict is advisory at account tier. Push and merge still wait for the founder's go.

## Tuning entry
- **2026-11-10** - blast-radius account - 17 findings; 0 false_alarm (2 no-change with reasons; 3 wrong line claims inside C4); tuning: none to the lenses.
  - Lens 5's refactor-onto-a-shared-helper sub-check found the one P1. A shared step's early return dropped what the
    old per-door path ran; the seat diffed the old `_persistCompletion` against the new step.
  - Splitting the seats by slice (rule and doors, bookkeeping, UI + docs) kept each brief narrow, and no two seats
    reported the same finding.
  - The author's mutation pass found two vacuous tests (a date that is padded today anyway, and a real-zone snackbar
    timer). "Mutate it and run it" stays the check that catches a test written the same day as its code.
