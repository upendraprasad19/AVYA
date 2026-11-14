---
bug_id: 2c9f7a
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: feature
symptom: >
  Train week strip, two issues: (3a) current-phase week chips never showed a
  completion check mark (only past-phase chips did), so a completed current week
  looked un-done; (3b) the strip was a bare horizontal scroll view with no
  auto-scroll — the user had to manually scroll to reach the current week.
concept: week_completion_check
sot_registry_entry: week_completion_check
writers: >
  WorkoutWriteService.markCompleted (sets schedule_* status='completed') —
  unchanged. New reader: WorkoutScheduleReadService.completedWeekNumbers (mirrors
  the past-phase "any completed day that week" rule via getScheduleForDate).
readers: >
  lib/features/train/widgets/week_selector.dart — _WeekChip now renders
  Icons.check_circle when hasCompletedDay && !isLocked; _PhaseGroup threads
  completedWeeks.contains(w); the parent computes service.completedWeekNumbers().
  Auto-scroll: ScrollController + Scrollable.ensureVisible on first layout +
  a contextual "TODAY →" pill (AnimatedOpacity) shown when the current phase is
  off-viewport.
hive_key_prefix: schedule_
hive_key_formula: not_applicable (reads existing schedule_<istDate> rows via getScheduleForDate)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: scheduled_workouts
cloud_columns: not_applicable (read derives from local schedule_* status)
contract_test_path: test/contracts/week_completion_check_test.dart
ist_handling: not_applicable (getScheduleForDate handles the date→key conversion)
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (reads user-scoped workoutBox via existing guarded paths)
forbidden_patterns_checked:
  - "_WeekChip (current/forward phase chips) lacking any completed-week check rendering — now renders Icons.check_circle on hasCompletedDay && !isLocked; pinned by test/contracts/week_completion_check_test.dart."
  - "week_selector strip with no ScrollController / no auto-scroll to the current week — now auto-scrolls on open + a TODAY pill; pinned by the same test."
proposed_fix: >
  3a: WorkoutScheduleReadService.completedWeekNumbers({maxWeek}) returns global
  week numbers with ≥1 completed scheduled day (same rule as past-phase chips);
  the parent threads it into every _PhaseGroup → _WeekChip, which renders the same
  check_circle, guarded by !isLocked (no check on a paywalled/preview week).
  3b: add a ScrollController + GlobalKey on the current phase group; on first
  post-frame, Scrollable.ensureVisible the current phase; a scroll listener fades
  in a gold "TODAY →" pill when the current phase is off-viewport (tap → scroll back).
regression_test_planned: >
  test/contracts/week_completion_check_test.dart (comment-stripped source-grep):
  completedWeekNumbers + the any-completed-day rule exist; the parent threads
  completedWeeks into every _PhaseGroup; _WeekChip renders check on
  hasCompletedDay && !isLocked; ScrollController + ensureVisible + post-frame
  auto-scroll + the TODAY pill + controller disposal are all present.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "completedWeekNumbers added; _WeekChip check + auto-scroll + pill added; flutter analyze clean on week_selector.dart + workout_schedule_read_service.dart" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "reads existing schedule_* status; week_selector_past_phases + phase_progress_reconciler tests still green" }
impact_analysis: >
  Feature blast radius — Train display only. The check rule reuses the proven
  past-phase predicate so past + current chips agree. The auto-scroll/pill are
  additive UI (no data path). The founder's reported "W4 no check" is past-phase
  duplicate-week residue that re-restores correctly once +32+ is installed; the
  current-phase chips now check regardless. Found via the founder's APK image 3.
---

# Train week strip: missing current-phase checks + no auto-scroll

## What happened
Current-phase week chips never showed a completion check; the strip never
auto-scrolled to the current week.

## Root cause
`_WeekChip` (current/forward chips) had no checkmark logic at all — only
`_PastWeekChip` did. `week_selector` was a bare `SingleChildScrollView` with no
`ScrollController`.

## Fix
`completedWeekNumbers()` (any completed day that week) threaded into `_WeekChip`,
which renders the same `check_circle` (guarded by `!isLocked`). Added a
`ScrollController` + post-frame `ensureVisible` to the current phase + a
contextual "TODAY →" pill (founder-selected mockup).

## Verification
`flutter analyze` clean; `week_completion_check_test.dart`; existing
week-selector + reconciler tests green.

## See also
- `lib/features/train/widgets/week_selector.dart`
- `lib/core/services/workout_schedule_read_service.dart` (completedWeekNumbers)
