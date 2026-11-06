---
bug_id: 89d56c
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 3 / Theme F1)
status: shipped
symptom: |
  Founder unlocked Phase 2 graduation card 2026-05-21 and saw TOTAL
  SETS = 0 alongside 30 PRs / 15 workouts / 2 week streak. Cloud data
  shows hundreds of completed sets across Phase 1. Every user on every
  phase unlock since Test #6 has seen the same 0 — the bug is universal,
  not founder-specific.

  Root cause: graduationStatsProvider at
  lib/features/train/providers/train_provider.dart:1736 iterated
  workoutBox.values, filtered by `log['type'] == 'exercise_log'` (a
  field WorkoutWriteService never writes — `type` is unset on every
  exlog_* row), AND read `log['sets_completed']` (legacy field name;
  the canonical writer field has been `set_number` since the Test #6
  WriteService rewrite per hive_field_name_exlog SoT). Both wrong:
  the filter excluded EVERY row, so the inner aggregation never ran.

  Sibling drift: PR count counted per-log `is_pr` boolean flags. The
  canonical source for the PR set is `allExercisePRsProvider` at
  home_provider.dart:825 (delegates to
  WorkoutRepository.loadAllExercisePRs which computes best-per-set
  via WorkoutReadService). Counting per-log flags drifts because
  (a) sync-restore may carry stale is_pr flags from older clients,
  (b) the per-set MAX semantic was extracted to WorkoutReadService
  in OI-02/OI-08 but the graduation reader still inlined a stale
  per-log weight comparison.

  10th instance of writer/reader drift per debugging skill §2.1.
concept: exercise_logs_read_path
sot_registry_entry: workout_logs
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: WorkoutWriteService.logExercise — writes set_number, exercise_name, weight_kg, etc. (no `type` field, no `sets_completed`), line: 166 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: graduationStatsProvider — fixed to walk exlog_* keys + read set_number with sets_completed fallback + delegate PR count to allExercisePRsProvider, line: 1727 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: loadAllExercisePRs (canonical PR computation), line: 622 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: allExercisePRsProvider (canonical PR provider), line: 825 }
hive_key_prefix: "exlog_"
hive_key_formula: "exlog_${istDateStr(date)}_${exerciseName.hashCode.toUnsigned(32).toRadixString(16)}"
sync_methods: []
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: [exercise_name, set_number, reps_completed, weight_kg, volume_kg, is_pr, logging_type, workout_log_id]
contract_test_path: test/contracts/graduation_stats_provider_field_test.dart
ist_handling:
  - { file: lib/features/train/providers/train_provider.dart, line: 1727, source: "no date-key math in this provider — aggregation only" }
provider_invalidations:
  - graduationStatsProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: provider already ref.watches authUserIdTokenProvider at line 1728 — rebuild on auth change c4055a.
forbidden_patterns_checked:
  - "filtering by log['type'] when the writer never sets the type field"
  - "reading log['sets_completed'] without a fallback chain to canonical set_number"
  - "computing PR set inline rather than delegating to allExercisePRsProvider canonical reader"
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "train_provider.dart:1727 — graduationStatsProvider rewritten" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Hive keys + field names confirmed via grep against WorkoutWriteService.logExercise (set_number written at workout_write_service.dart:171)" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/graduation_stats_provider_field_test.dart — 4 source-grep assertions pinning the canonical aggregation pattern" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/graduation_screen.dart (reads graduationStatsProvider)
  callers_updated_in_this_batch:
    - lib/features/train/providers/train_provider.dart (graduationStatsProvider rewritten in place)
  callers_unchanged:
    - All consumers — provider signature returns the same GraduationStatsData shape; only the math inside changed.
proposed_fix: |
  Rewrite graduationStatsProvider body (train_provider.dart:1727-1785):

  1. Total sets — walk `exlog_*` keys directly (canonical pattern from
     loadAllExercisePRs at workout_repository.dart:622). For each row
     read `set_number` (canonical) with `sets_completed` fallback for
     legacy rows. Drop the type filter entirely.

  2. PR count + top PRs — `ref.watch(allExercisePRsProvider)`. Count is
     `allPrs.length`. Top 3 sorted by `pr.bestValue` descending. Display
     uses `pr.formattedValue` which already renders kg/reps/seconds/km
     correctly per logging_type.

  No behavioral signature change — provider still returns
  GraduationStatsData with the same 5 fields. Consumers unchanged.
regression_test_planned:
  - test/contracts/graduation_stats_provider_field_test.dart — 4 assertions: (1) no `type == 'exercise_log'` filter, (2) walks `exlog_` keys, (3) reads `set_number` with `sets_completed` fallback, (4) delegates PR to allExercisePRsProvider.
recurrence: |
  10th instance of writer/reader drift per debugging skill §2.1.
  Variants previously seen:
    - Test #6  Bug a8f1c2 — sets_completed/set_number  (latest set widget — first such drift surfaced)
    - Test #8        — 4 ai_coach_repository drift fixes
    - Test #11.1     — istDateStr double-shift (semantic drift, same class)
    - Test #12       — formatDateKey UTC drift (semantic)
    - Test #15.3 Bugs 1/6/7 — three concurrent field-name drifts
    - Test #16.1 Theme A — 3 rogue exlog_ key formulas
    - Test #16.2 E   — logPR AI coach tool through WriteService
    - Test #16.2 9th — coach_memory.coach_notes upward sync
    - 10th: THIS bug — graduation reader's `type` filter + sets_completed
            field-name + per-log is_pr count
  The class enforcement story:
    - Source-grep contract tests count for presence only
      (feedback_source_grep_false_confidence.md); they did NOT catch this
      because no test asserted "graduation reader uses canonical
      aggregation". This fix lands a contract test (presence) — the
      durable mitigation is Theme G Gate 19 (Hive Map field-key drift
      detector) ALSO landing this batch.
related_bugs:
  - a8f1c2  # Test #6 founding instance of sets_completed/set_number drift
  - Test #16.1 / a16c1a  # Most recent prior instance — 7th drift
---
# Body

## Why this drifted

The Test #6 WriteService rewrite renamed `sets_completed` → `set_number`
on the writer side. Most consumers were updated; this graduation
reader was missed because it lived inside a Provider lambda (not a
WriteService callsite the source-grep checked) AND the cosmetic
`type == 'exercise_log'` filter made it look like the reader was
already opinionated about its row shape — when in fact the filter
silently excluded everything.

## Why the fix uses allExercisePRsProvider rather than re-computing

`allExercisePRsProvider` delegates to `loadAllExercisePRs` which uses
`WorkoutReadService.bestPerSetWeight / bestPerSetReps /
bestPerSetDuration` per logging_type. The pre-fix graduation reader
hardcoded `log['weight_kg']` which is the LATEST log's top-level
weight, not the per-set MAX — drifted from the canonical PR semantic
since OI-02/OI-08 split per-set computation into WorkoutReadService.
Delegating fixes both the count AND the displayed top-3 values.

## What "TOTAL SETS = 0" looked like on phase unlock

Graduation screen pre-fix: `total workouts: 15  total sets: 0
total PRs: 30  streak: 2 weeks`. Founder saw `0 sets` next to `15
workouts` and `30 PRs` — visibly inconsistent (you can't have PRs
without sets). The math comes back correct in this batch.

## Why this affects every user, not just the founder

The drift was in the AGGREGATION code, not in any per-user data. Every
account's exlog_* rows have the canonical `set_number` field set
correctly by WorkoutWriteService and zero rows have a `type` field.
The reader's wrong predicate excluded everything on every account.
Test #16.2 +31 ships the fix universally.
