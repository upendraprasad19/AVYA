---
bug_id: 5c8e2a
date: 2026-11-23
batch: oi348-walk-fixes Landing 1b (B3/B7)
status: fixed
tier: full
blast_radius: account
symptom: |
  OI-348 walk A5 part 1 (AAB 1.0.0+50, Upendra, 2026-11-22): the Train strip's past "Phase I" week 2 sheet ("Completed history") listed only Sun 27 Sep (rest) and Mon 28 Sep, while the cloud had Tue 29 Sep - Fri 2 Oct completed (Oct 1 "PULL + CORE"). Past phase chips read odd ranges: Phase II from Apr 27, Phase III ending Jun 28, Phase IV from Oct 12.
concept: past_phase_display_buckets
sot_registry_entry: past_phase_display_buckets
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "generateAndSchedule / generateAndScheduleFromDate (stamp `phase` on every schedule_* row of a window at write time)", line: 301 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method_or_widget: "mergeScheduleEntry L1 guard (keeps a local rest row wholesale, stale stamp included)", line: 102 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "bucketPastRowsForDisplay (new, date-ordered display bucketing)", line: 2113 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "pastPhaseBlocksForDisplay (both branches use it, switch on)", line: 1981 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "phaseForDate / phaseForDateDisplay (receipt phase label = chip number)", line: 2220 }
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: "_toPastPhases (weekCount) / _PastPhaseGroup (one chip per week spanned)", line: 340 }
hive_key_prefix: "schedule_ (workoutBox, unchanged)"
hive_key_formula: "schedule_<yyyy-MM-dd> (unchanged)"
sync_methods: []
restore_methods: [PlanIntegrityReconciler.mergeScheduleEntry]
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: test/contracts/past_phase_display_runs_behavioral_test.dart
ist_handling: ["rows are grouped by their stored date strings (IST day keys already); the Mon-Sun week of the edge rule and the chip count use UTC calendar dates built from those strings, never a clock"]
provider_invalidations: ["none: a pure read at WeekSelector.build and at receipt build; no new provider"]
telemetry_op_types:
  success: []
  failure: [phase_for_date_fallback]
cross_account_guard: "true: reads only the current owner's workoutBox through WorkoutScheduleReadService (wrapUserScopedBox); writes nothing."
forbidden_patterns_checked:
  - { pattern: "a change to the strict pastPhaseBlocks() that PhaseProgressReconciler and pro_phase_advance count", absent: true }
  - { pattern: "a write to schedule_* rows or to the L1 merge", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing1b.md (v3 FINAL, review 2 rounds, converged). DISPLAY ONLY. New pure bucketPastRowsForDisplay: runs of equal stamp over the STAMPED rows only (an unstamped row never joins or breaks a run); a run of at most 2 rows that are all rest rows is noise (the only rows the L1 merge keeps with a stale stamp), unless every run is noise; noise dropped, adjacent equal segments merged; every row assigned by date to the last segment starting on or before it, with an edge rule (an unstamped or noise row after the previous segment's last stamped day and in the same Mon-Sun week as the next segment's first stamped day joins that next segment). pastPhaseBlocksForDisplay uses it in both branches; phaseForDate keeps its current-window short-circuit first and then labels a past date with the chip number (phaseForDateDisplay, same slice as _toPastPhases, implemented independently); a past group shows one chip per week its rows span (min 4). Kill switch configBox disable_past_phase_display_runs (read per call in the service, once per WeekSelector build) restores the stamp-number grouping, 4 chips and the strict-index receipt verbatim.
regression_test_planned: |
  test/contracts/past_phase_display_runs_behavioral_test.dart (24 tests, incl. the B-pass DST week helper and the one-chip-per-row check): T1 the walk account's 140 live past rows verbatim (5 blocks, Sep 28-Oct 4 whole, no date twice, and the old grouping's 5-day "Phase I" pinned as the diagnosis); T2 clean history equal to bucketPastRows (bounds, dates, row identity); T3/T4 F-B (gap, held phase, 5 chips); T5 restart and non-adjacent equal stamps; T6/T10 noise and its mirrors (1 stray, consecutive noise, rest-only 3 rows, 1 workout row, workout + rest, all noise); T7 Sundays stamped 1 around unstamped completed days; T8/T8b edge rule and its mid-week mirror; T9 no stamps; phaseForDateDisplay slices; Hive: every listed row reads its group's number (two implementations), gap dates, the hidden block, the switch in both branches, and T11 (a current-window receipt walks no rows).
mutation_proof: |
  Rule 21. scratchpad/mut_b3.sh: each mutant applied by sed to the live file, grep -c of the mutated text = applied, the test file run, both files restored by cp and cmp-identical after every mutant (never git checkout). 10 of 10 red:
  M1 always the stamp-number grouping (`return bucketPastRows(rows)`) red 11; M2 noise threshold 0 red 4; M3 noise without the rest-only condition red 2; M4 no merge of equal segments after dropping noise red 4; M5 edge rule removed red 5; M5b edge rule without the "after the previous segment's last stamped day" bound red 1; M6 phaseForDateDisplay returns the raw index red 3; M7 weekCount fixed at 4 red 2; M8 kill switch inverted red 3; M9 phaseForDate's current-window short-circuit removed red 1.
  The plan's M3 (runs built with carry-forward over unstamped rows) has no clean single-line form; it was replaced by the rest-only noise mutant, and the carry-forward shape is pinned behaviourally by T7.
  B-pass (review `docs/reviews/oi348-landing1b-bpass.md`, seat A: 0 P0/P1, its own 4 mutants all red): the chip COUNT used calendar days while the row-to-chip ASSIGNMENT used 7 x 24 h windows, which disagree across a DST change (an empty last chip, a row on the previous chip). Both now use one helper, `pastPhaseWeekOf` (calendar UTC day difference). New tests: the DST-shaped helper test and "every listed row on exactly one chip, last chip of an extended group not empty". Mutants (scratchpad/mut_bpass.sh): X1 floor to truncation, X2 entriesForWeek off by one, X3 hasCompletedDayInWeek off by one; results in the review file.
impact_analysis: |
  Every account with past phases sees date-ordered history: a past week lists every row of its dates and every row of a block sits on a chip. A clean account (non-decreasing stamps, each phase contiguous, 3+ stamped rows per phase) gets the same blocks as before (T2, and past_phase_display_recovery test D). The receipt phase label for a past date now equals the chip that lists it. The strict count that advances current_phase is unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "workout_schedule_read_service.dart (bucketPastRowsForDisplay, phaseForDateDisplay, switch getter, wrapper + phaseForDate wiring), week_selector.dart (weekCount); flutter analyze clean on both." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Read-only over schedule_* rows; the Hive tests seed the walk account's rows and read them back through the real service." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only query of user_progress.plan_json.schedules for the walk account (168 rows, 2026-11-23): the four Sunday rest rows stamped 1 inside the Sep 14-Oct 11 phase-3 window, unstamped completed rows, current_phase 5, plan_start 2026-11-09; the test fixture is those rows." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "None." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "plan_json schedules are mirrored to Hive by the restore; the fix reads the mirrored rows only and changes no push." }
recurrence: "Related to, not a recurrence of, 7d2e6b (28-day calendar windows split one long phase; fix F-B grouped by stamp, which this keeps for clean data) and c9e4b7 / b7f1c8 (display recovery when the strict set is empty; the recovery branch now uses the same display bucketing). New class: a write-time stamp trusted over the date sequence."
related_bugs: [7d2e6b, c9e4b7, b7f1c8, b6e1c8]
---

# 5c8e2a - past-phase-display-runs

## What happened
`bucketPastRows` grouped every past `schedule_*` row by its stamped `phase` number, ignoring dates. Each generator stamps the phase current at write time, and the L1 merge (`b6e1c8`, `plan_integrity_reconciler.dart` L1 guard) keeps a local rest row wholesale, stale stamp included, while the workout rows next to it take the incoming content. On the walk account, four Sunday rest rows inside a phase-3 month still said `phase: 1`. The grouping built "Phase I" from those Sundays plus a carried Monday, so its week 2 held Sun 27 and Mon 28 only. Blocks of the same number from different months merged into months-wide blocks, and the strip drew 4 chips per block, so most of their rows were on no chip.

## The writer of the stale stamps
Every generator writes all days of a window with one stamp. The first writer of the `1`s on those four dates is not identifiable from current code: the only `?? 1` fallbacks (`train_provider.dart:802`, `auth_session_bootstrapper.dart:983-986`, `edit_profile_screen.dart:2336`) fire only with no local progress, where 1 is the right default. The L1 guard is correct for its purpose and is not changed: adopting the incoming stamp has an unresolvable mirror (when the local stamp is the fresh one, the incoming one is stale).

## The fix
Display-only date-ordered bucketing (frontmatter `proposed_fix`). On the walk account: Apr 27-May 31 (hidden, oldest), Phase I Jun 1-Jul 23 (8 chips), Phase II Aug 19-25, Phase III Sep 14-Oct 11, Phase IV Oct 12-Nov 8. Phase III week 3 (Sep 28-Oct 4) lists all seven days.

## Residual, stated
- The strict `pastPhaseBlocks()` (counted by `PhaseProgressReconciler`, `phase_progress_reconciler.dart:131`, and `pro_phase_advance.dart:725`) still groups by stamp number. A stale lower stamp adds a block there only when no real past row carries that number; for an account whose history began at phase 1 that cannot happen, and on the walk account the strict count (4) is a no-op against `current_phase` 5. It is a monotonic counter risk only for an account whose early rows were deleted.
- A churned account shows long or short past groups (the walk account's 3-day Phase II is a real regeneration that wrote Aug 23-25 stamped 2). Past hold weeks show as W5+.
- A past-date receipt in the recovery branch used to read 1; it now reads the chip number (intended).
- Noise is a run of at most 2 stamped rows that are all rest rows (the recorded rule). Three or more CONSECUTIVE stale rest rows with no stamped row between them form a real segment, so a spurious short group; a genuine past phase made only of 1-2 rest rows is absorbed by date. Neither shape is in the walk account's data (its stale rows are single Sundays).
- `phaseForDate` reads `current_phase` from Hive while the strip uses the widget's `currentPhase`; the two can differ for one frame after a phase advance.
- The kill switch is removed after the device re-check (OI-524).
