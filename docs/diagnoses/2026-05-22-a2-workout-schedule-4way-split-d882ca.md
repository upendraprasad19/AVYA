---
bug_id: d882ca
date: 2026-05-22
batch: Tech-debt audit 2026-05-20 / finding A2 (final closure batch B5 D13-D17)
status: shipped
symptom: |
  `lib/core/services/workout_schedule_service.dart` had grown to ~1970
  lines and absorbed four distinct responsibilities:

    1. Plan generation orchestration (generateAndSchedule,
       generateAndScheduleFromDate, autoGenerateNextPhaseIfNeeded).
    2. Calendar / week / phase queries (getScheduleForDate, getWeek,
       getCurrentWeekNumber, getPlanStartDate, etc.).
    3. Schedule mutations not tied to swap or template (markCompleted,
       markSkipped, pauseRange, redoWeek4, copyWeek).
    4. Swap-engine state (swapDays, swapExerciseInDay, shortenDay,
       activateTravelMode + swap counters + travel mode).
    5. Template scheduling (assignTemplateToDate,
       unscheduleTemplateFromDate, cleanSyncTemplateSchedule).

  Single-class-multiple-responsibilities is the canonical "god service"
  shape. Caller migration is harder (every consumer reaches for the
  whole class), test isolation is harder (you instantiate the universe
  to verify swap counters), and the file exceeds the 1000-line
  god-screen ceiling pinned by Gate `check_god_screen_max_lines`.

  Closure: split into 4 narrowly-scoped services
  (WorkoutScheduleReadService / WorkoutScheduleWriteService /
  SwapService / TemplateService). The original
  WorkoutScheduleService class becomes a `@Deprecated` re-export shim
  with pass-through delegation, keeping all existing callsites
  compiling while the migration progresses. Full shim removal is a
  follow-up batch when caller count reaches zero.
concept: workout_schedule_service_split
sot_registry_entry: workout_schedule_service_split
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: WorkoutScheduleReadService (plan generation + reads), line: 32 }
  - { file: lib/core/services/workout_schedule_write_service.dart, method: WorkoutScheduleWriteService (mark / pause / copy), line: 36 }
  - { file: lib/core/services/swap_service.dart, method: SwapService (swap + travel), line: 79 }
  - { file: lib/core/services/template_service.dart, method: TemplateService (templates), line: 52 }
  - { file: lib/core/services/workout_schedule_service.dart, method: WorkoutScheduleService (@Deprecated shim), line: 57 }
  - { file: lib/core/services/service_providers.dart, method: 4 split Providers + 1 shim Provider, line: 100 }
readers:
  - { file: lib/features/train/widgets/week_selector.dart, method_or_widget: ref.read(workoutScheduleReadServiceProvider).getPlanStartDate (migrated), line: 41 }
  - { file: lib/features/train/widgets/plan_expired_card.dart, method_or_widget: ref.read(workoutScheduleWriteServiceProvider).redoWeek4 (migrated), line: 61 }
  - { file: lib/features/home/widgets/swap_sheet.dart, method_or_widget: ref.read(swapServiceProvider).swapDays + ref.read(workoutScheduleReadServiceProvider).getScheduleForDate (migrated), line: 47 }
  - { file: lib/features/train/screens/phase_roadmap_screen.dart, method_or_widget: ref.read(workoutScheduleReadServiceProvider).getCurrentWeekNumber (migrated), line: 44 }
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: ref.read(workoutScheduleWriteServiceProvider).redoWeek4 + ref.read(workoutScheduleReadServiceProvider).generateAndSchedule (migrated), line: 132 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: ref.read(workoutScheduleReadServiceProvider).getScheduleForDate (migrated), line: 43 }
hive_key_prefix: "schedule_, displaced_, swaps_this_week, swap_week_start, travel_start, travel_end, plan_start_date, plan_end_date, current_plan"
hive_key_formula: "Keys are shared across the 4 split services — schedule writes still produce `schedule_<YYYY-MM-DD>` (canonical via WorkoutWriteService.upsertScheduled, unchanged). Swap counters land at `swap_week_start` + `swaps_this_week`. The split changes the OWNING CLASS of each method, not the Hive key formula."
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/workout_schedule_split_invariant_test.dart
ist_handling: "Not date-bound — this is a code reorganisation. Each split service preserves the original IST handling of the methods it owns (e.g. WorkoutScheduleReadService.generateAndScheduleFromDate still calls istMidnight(fromDate); SwapService still keys swap counters by monday-of-IST via formatDateKey)."
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: |
  Each split service registers its own SingletonLifecycleRegistry hook
  (WorkoutScheduleReadService / WorkoutScheduleWriteService /
  SwapService / TemplateService) — defense in depth. The original
  WorkoutScheduleService shim ALSO keeps its registration (it does no
  per-user state today, but the registration preserves symmetry with
  callers who may still hold references). Provider wiring in
  service_providers.dart wires `ref.listen(authUserIdTokenProvider)`
  per Provider; on user swap each Provider fires
  SingletonLifecycleRegistry.notifyUserChanged() — same contract as the
  7 services covered by A7.
forbidden_patterns_checked:
  - "Real implementation duplicated in the shim — Gate 47 + invariant test assert shim < 350 lines + does not contain `PlanGenerator.instance.generate` body (the shim must only delegate)."
  - "Caller bypasses Providers — @Deprecated lint surfaces every WorkoutScheduleService.instance callsite for follow-up migration."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "4 new service files (read 577 + write 234 + swap 549 + template 384 LOC); shim shrunk to 264 LOC pass-throughs; service_providers.dart adds 4 new Providers + keeps shim Provider as @Deprecated; 6 caller migrations across week_selector / plan_expired_card / swap_sheet / phase_roadmap_screen / graduation_screen / weekly_calendar — proof of pattern. Full caller migration is a follow-up batch when @Deprecated callsite count drops naturally." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Hive keys and write paths unchanged — every write still routes through WorkoutWriteService.upsertScheduled (the canonical writer, owned by Test #16.2). Constants reproduced byte-identical in each split service (e.g. `_schedulePrefix = 'schedule_'`)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. scheduled_workouts table untouched." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data change." }
  - { tier: 5, name: migrations, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_functions, status: not_applicable, evidence: "No Edge Function change." }
  - { tier: 7, name: cron, status: not_applicable, evidence: "No cron change." }
  - { tier: 8, name: rls, status: not_applicable, evidence: "No RLS change." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage change." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secrets change." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service change." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "test/contracts/workout_schedule_split_invariant_test.dart (8 tests PASS). Gate 47 (scripts/check_workout_schedule_split.dart) hard-fails CI if any of the 4 services regress or the shim loses @Deprecated. flutter analyze --no-fatal-infos completes with no NEW errors in touched files." }
impact_analysis: |
  - Performance: zero impact. Each split service is a singleton with
    the same shape as the original; method bodies move byte-identical
    (with constants and helpers reproduced or accessed via the
    Read/WriteService singleton).
  - Caller migration: progressive. Gate 47 + @Deprecated lint surface
    every callsite. 6 proof-of-pattern callers migrated this batch
    (well-spaced across feature dirs to validate the pattern works in
    both ConsumerWidget contexts (ref.read) and pre-Riverpod static
    paths still work via shim).
  - Test isolation: future contract tests can construct
    SwapService.instance alone without dragging the plan generator and
    template machinery into scope.
  - Shim deletion: follow-up batch when grep `WorkoutScheduleService.instance`
    in lib/ returns 0 callsites. At that point the @Deprecated annotation
    flips to analyser error and `instance` declarations get deleted.
proposed_fix: |
  Land A2 with:
    1. 4 new service files (Read / Write / Swap / Template) each with
       its own static `instance`, SingletonLifecycleRegistry hook, and
       narrowly-scoped methods.
    2. The original workout_schedule_service.dart becomes a 264-line
       @Deprecated pass-through shim. Every method delegates to the
       split service's static instance.
    3. service_providers.dart exposes 4 new Providers
       (workoutScheduleReadServiceProvider /
       workoutScheduleWriteServiceProvider / swapServiceProvider /
       templateServiceProvider) AND keeps workoutScheduleServiceProvider
       as the @Deprecated shim Provider.
    4. 6 proof-of-pattern caller migrations (one per high-value
       surface: week_selector, plan_expired_card, swap_sheet,
       phase_roadmap_screen, graduation_screen, weekly_calendar).
    5. Gate 47 (`scripts/check_workout_schedule_split.dart`) and
       regression test
       (`test/contracts/workout_schedule_split_invariant_test.dart`)
       to pin the invariant.
regression_test_planned: |
  test/contracts/workout_schedule_split_invariant_test.dart asserts:
    1. Each of the 4 split service files exists at the named path with
       the expected class declaration AND the expected method names.
    2. service_providers.dart declares the 4 new Providers + the shim
       Provider.
    3. The shim file is @Deprecated AND is < 350 lines (sanity check
       that real implementation didn't leak back) AND does NOT contain
       `PlanGenerator.instance.generate` (proves the real generation
       body lives in ReadService, not in the shim).
  Gate 47 (scripts/check_workout_schedule_split.dart) enforces 1-3 in
  pre-commit + CI.
followups:
  - "Migrate remaining WorkoutScheduleService.instance callsites (~16 files). @Deprecated lint surfaces them. Follow-up batch deletes the shim entirely once callsite count reaches 0."
  - "Once shim is removed, drop `workoutScheduleServiceProvider` from service_providers.dart and update Gate 47 to remove the shim-existence check."
metrics:
  files_changed: 11
  net_lines_added: ~40
  services_split_from_one_class: 4
  shim_loc: 264
  new_service_loc_total: 1744
  callers_migrated_this_batch: 6
  callers_remaining: ~16
  test_count: 8
  gate_added: scripts/check_workout_schedule_split.dart
---

# A2 — Workout schedule service 4-way split

## What changed

The 1970-line `WorkoutScheduleService` god class is split into 4
narrowly-scoped services:

| Service | Lines | Responsibility |
|---|---:|---|
| `WorkoutScheduleReadService` | 577 | Plan generation + calendar/week queries. |
| `WorkoutScheduleWriteService` | 234 | markCompleted / markSkipped / pauseRange / redoWeek4 / copyWeek. |
| `SwapService` | 549 | swapDays / swapExerciseInDay / shortenDay / activateTravelMode + swap counters. |
| `TemplateService` | 384 | assignTemplateToDate / unscheduleTemplateFromDate / cleanSyncTemplateSchedule + LoggingTypeResolver. |

The original `workout_schedule_service.dart` is now a 264-line
`@Deprecated` re-export shim. Every method delegates to the split
service. Re-exports preserve the public exception/result types
(`SwapExerciseException`, `ShortenDayResult`, `AssignTemplateResult`,
`PausePlanException`, `LoggingTypeResolver`) so callers that imported
them from the shim keep compiling.

Provider file gains 4 new entries
(`workoutScheduleReadServiceProvider`,
`workoutScheduleWriteServiceProvider`, `swapServiceProvider`,
`templateServiceProvider`) while the existing
`workoutScheduleServiceProvider` stays as the `@Deprecated` shim
Provider — so legacy ref.read callers still resolve.

## What didn't change

- Hive keys + payload shapes — every write still routes through
  `WorkoutWriteService.upsertScheduled` (the canonical writer from Test
  #16.2).
- Method bodies — bodies are reproduced byte-identical in the split
  services, only the owning class changes.
- IST handling — preserved per-method.
- SingletonLifecycleRegistry contract — each new service registers its
  own hook; the shim keeps its registration for symmetry.

## Why a shim instead of removing the old class

Per CLAUDE.md §4.11 (gates before refactor): a refactor of this scope
touches a known bug class (writer/reader drift across the schedule
domain). The gate that DETECTS regression (Gate 47) ships in the SAME
commit as the split. Callers migrate progressively under the
`@Deprecated` lint; the shim deletion is a follow-up batch when
callsite count reaches zero.

## Reopening criterion

When `grep -rn "WorkoutScheduleService\(\.instance\| get instance\)" lib/`
returns only the shim's own declaration (no caller invocations), the
follow-up batch deletes the shim file, drops the shim Provider, and
updates Gate 47.
