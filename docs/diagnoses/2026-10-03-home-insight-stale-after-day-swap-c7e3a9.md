---
bug_id: c7e3a9
date: 2026-10-03
batch: swap-cross-device-reconcile
status: fixed
blast_radius: feature
symptom: |
  Founder-reported (2026-10-01, observation 2 of the day-swap report): after
  swapping today's workout with tomorrow's, Home's AI-coach insight sentence
  kept naming the pre-swap workout while the rest of Home moved on. Code
  read: the insight is computed by AiInsightNotifier, which read today's
  schedule row with ref.read and therefore recomputed only when a writer
  ALSO remembered to invalidate aiInsightProvider. The day-swap provider
  batch (and ~15 other writers of today's row) invalidates
  todayWorkoutProvider but not aiInsightProvider.
concept: scheduled_workouts_mutations
sot_registry_entry: |
  scheduled_workouts_mutations — EXISTING concept (docs/sot_registry.yaml:420,
  behavioral_test_path already set at :422). This batch updates its existing
  aiInsightProvider reader row (:474-478): line_range and fields_read now say
  the insight reads today's row via todayWorkoutProvider.
writers:
  - { file: lib/features/train/providers/day_swap_provider.dart, method_or_widget: "DaySwapController._refresh — invalidates todayWorkoutProvider, not aiInsightProvider", line: 75 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "swapScheduledDays / markCompleted / upsertScheduled — the Hive writes of schedule_<date>", line: 493 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "AiInsightNotifier.build — now ref.watch(todayWorkoutProvider)", line: 661 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "TodayWorkoutNotifier.build — the row the Today card and now the insight both read", line: 521 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "insight card — ref.watch(aiInsightProvider)", line: 742 }
hive_key_prefix: "schedule_ (workoutBox)"
hive_key_formula: "'schedule_${formatDateKey(DateTime.now())}'"
sync_methods:
  - "none touched — local provider dependency only"
restore_methods:
  - "none touched — the launch restore never invalidating todayWorkoutProvider is OI-294"
cloud_table: null
cloud_columns:
  - null
contract_test_path: test/contracts/ai_insight_follows_today_row_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_dateKey -> formatDateKey -> istDateStr (unchanged)", line: 2083 }
provider_invalidations:
  - "todayWorkoutProvider (now cascades to aiInsightProvider through ref.watch)"
  - "aiInsightProvider (existing explicit invalidations kept)"
telemetry_op_types:
  success:
    - none
  failure:
    - none
cross_account_guard: "Unchanged: AiInsightNotifier and TodayWorkoutNotifier both ref.watch(authUserIdTokenProvider) (c4055a); the insight keeps its own watch, pinned per Notifier by test/contracts/auth_invalidation_contract_test.dart:34."
forbidden_patterns_checked:
  - { pattern: "ref.read(workoutScheduleServiceProvider) inside AiInsightNotifier", absent: true }
  - { pattern: "dependency cycle todayWorkoutProvider -> aiInsightProvider", absent: true }
proposed_fix: |
  AiInsightNotifier.build computes the sentence from
  ref.watch(todayWorkoutProvider) instead of its own
  ref.read(workoutScheduleServiceProvider).getScheduleForDate(now). Both read
  the same row with the same clock (TodayWorkoutNotifier.build uses the same
  service call with DateTime.now()), so the sentences are byte-identical; the
  difference is only WHEN the insight recomputes: now whenever the Today card
  does. Debugging class 2.58's fix pattern: derive from one source rather
  than add one more entry to an invalidation list.
regression_test_planned: |
  - test/contracts/ai_insight_follows_today_row_test.dart
    group 1 (BEHAVIORAL, the regression): real Hive session + real
    ProviderContainer, no todayWorkoutProvider override. Writes today's row
    "Push + Core", reads the insight, rewrites the row "Pull + Core",
    invalidates ONLY todayWorkoutProvider, asserts the insight names
    "Pull + Core". RED on the pre-fix code (Actual: 'Push + Core is
    scheduled for today — 3 exercises. Ready when you are!').
    group 2 (byte-identity, green before AND after): planned, completed,
    rest, logged with the OI-126 flag OFF and ON, terminal moved row, no row
    — each existing sentence exactly.
  Mutation (rule 21): replaced ref.watch(todayWorkoutProvider) with the old
  ref.read(workoutScheduleServiceProvider).getScheduleForDate(now); grep -c
  confirmed it applied (1); the file went +7 -1 — exactly the group-1 test
  reddened, as predicted in the plan. Restored and cmp-verified.
impact_analysis: |
  Scoped to the Home insight card's first line. After the fix it is exactly
  as fresh as Home's Today card: every writer that refreshes the card
  (21 invalidate(todayWorkoutProvider) sites) now refreshes the insight.
  Not fixed here, each on the OI board: the cross-device launch restore
  never invalidates todayWorkoutProvider (OI-294); ref-less writers such as
  deload_evaluator.dart:223 refresh neither (OI-295); the completed-row
  title freeze that made the founder's Oct 1 row wrong in Hive (OI-284).
  Behaviour change: between midnight and the rollover timer a nutrition
  write used to re-read today's row; it now shows the cached row, the same
  as the Today card (bounded by day_rollover_service's timer).
related_bugs:
  - b3c9d4
  - 9c8958
  - bae4dd
recurrence: |
  6th instance of debugging class 2.58 (.claude/skills/debugging/bug-classes.md):
  b3c9d4 (profile providers, restore tick list), 9c8958 / bae4dd (rollover
  list), F5 (test/providers/ai_insight_invalidation_test.dart, insight
  invalidation call sites). Applied the class's known-good fix (derive).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "home_provider.dart AiInsightNotifier watches todayWorkoutProvider; flutter analyze lib/ shows no warning/error; mutation reddened the regression test (+7 -1)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Reads only schedule_<IST today> via the unchanged WorkoutScheduleReadService.getScheduleForDate; the test writes and reads real Hive rows in a per-user session." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No cloud read or write involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Purely local provider dependency; the cross-device path is OI-294." }
---

## Summary

Home's insight sentence named the pre-swap workout after a day swap. It
read today's row once and recomputed only when a writer also invalidated
`aiInsightProvider`; the day-swap batch did not. The insight now watches
`todayWorkoutProvider`, so it follows the Today card.

## Root cause

Reader `AiInsightNotifier` (`lib/features/home/providers/home_provider.dart:649`)
used `ref.read(...)` for today's row. Writers of that row refresh the Today
card through `invalidate(todayWorkoutProvider)` at 21 sites; only 7 files
also invalidate `aiInsightProvider`. The day-swap provider batch
(`lib/features/train/providers/day_swap_provider.dart:75-82`) is one of the
misses, as are swap sheets, the edit-log sheet, the chat log, coach tools and
template edits.

## Fix

Derive: `_computeScheduleInsight(ref.watch(todayWorkoutProvider))`. Precedent
in the same file: `StreakWarningEligibilityNotifier` (`home_provider.dart:369`).

## Related

Plan `docs/plans/swap-cross-device-reconcile.md` v6 (review rounds 5-6). The
rest of the founder's day-swap report is on the OI board: OI-284, OI-292..295.
